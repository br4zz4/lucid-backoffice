require "lucid/backoffice/action/field"
require "lucid/backoffice/action/preview"
require "lucid/backoffice/action/runner"

module Lucid
  module Backoffice
    # A corrective action: the only way the back office writes. Declare what you need and the gem
    # derives the preview, the state check, the reason, the permission and the activity event.
    #
    #   class ChangeUserRole < Lucid::Backoffice::Action
    #     on :users
    #     field :role, :select, choices: -> { %w[teacher coordinator] }
    #     unavailable "School would have no owner", if: -> { record.last_owner? }
    #     perform { record.update!(role: role) }
    #   end
    class Action
      Failure = Data.define(:type, :errors) do
        def failure? = true

        def [](key) = key.to_sym == :errors ? errors : nil
      end

      Result = Data.define(:status, :message, :value, :redirect, :secret) do
        def initialize(status:, message:, value:, redirect: nil, secret: nil) = super

        def ok? = status == :ok
      end

      class << self
        def inherited(subclass)
          super
          Action.registry << subclass
        end

        def registry
          @registry ||= []
        end

        def reset!
          registry.clear
        end

        def for_key(key)
          registry.find { |action| action.key == key.to_s }
        end

        def for_target(target)
          registry.select { |action| action.target == target.to_s }
        end

        def key
          name.to_s.demodulize.underscore
        end

        # @param collection [Boolean] the action is on the table as a whole (no record), offered in the header of its list
        def on(target = nil, collection: false)
          if target
            @collection = collection
            @target = target.to_s
          else
            @target
          end
        end
        alias_method :target, :on

        def collection?
          @collection == true
        end

        # Where the operator lands after a successful run when the app gave no +redirect_to+: the +:record+
        # the action created, or the +:list+ of its table.
        def landing(kind = nil)
          kind ? @landing = kind.to_sym : @landing
        end

        def label(text = nil)
          return(@label = text) if text

          @label.respond_to?(:call) ? @label.call : (@label || key.humanize)
        end

        def permission(name = nil)
          name ? @permission = name.to_sym : (@permission || :run_action)
        end

        def danger(level = nil)
          level ? @danger = level.to_sym : (@danger || :normal)
        end

        def transaction(value = nil)
          value.nil? ? (@transaction.nil? ? true : @transaction) : @transaction = value
        end

        def field(name, type = :string, choices: nil, default: nil, of: nil, scope: nil, partial: nil, required: true)
          fields[name.to_sym] = Field.new(name: name.to_sym, type: type, choices: choices, default: default, of: of, scope: scope,
                                          partial: partial, required: required)
          define_method(name) { values[name.to_sym] }
        end

        def fields
          @fields ||= {}
        end

        def only_if(reason = nil, &block)
          conditions << { reason: reason, block: block }
        end

        def unavailable(message, if: nil, &block)
          guards << { message: message, block: binding.local_variable_get(:if) || block }
        end

        # One way to execute the action: each becomes a button at the final step, in the order declared,
        # and only the ones whose +if+ holds (evaluated in the action) are offered.
        def submit(key, label:, if: nil)
          submits << { key: key.to_sym, label: label, condition: binding.local_variable_get(:if) }
        end

        def submits = (@submits ||= [])

        def conditions = (@conditions ||= [])
        def guards = (@guards ||= [])

        def preview(&block)
          block ? @preview = block : @preview
        end

        # The write. A block, or +with:+ a Lucid::Case Command (its attributes are the fields, plus
        # +record+ and +tenant+ when it declares them); its failures show their +errors+ message.
        def perform(with: nil, &block)
          @perform_with = with if with
          block ? @perform = block : @perform
        end

        def perform_with
          @perform_with
        end

        # A value handed back to the operator once, right after the action runs, to be copied and passed on
        # (a set-password link, a token). +secret { |value| string }+; nil or blank means there is none.
        def secret(&block)
          block ? @secret = block : @secret
        end

        def result(&block)
          block ? @result = block : @result
        end

        # Where the operator goes after a successful run, instead of back to the screen it came from:
        # +redirect_to { |value| url }+, evaluated in the action. The URL comes from the app, never from a parameter.
        def redirect_to(&block)
          block ? @redirect_to = block : @redirect_to
        end
      end

      attr_reader :record, :tenant, :params, :values, :reason, :submitted

      def initialize(record: nil, tenant: nil, params: {}, reason: nil, submit: nil)
        @submitted = submit.presence&.to_sym
        @record = record
        @reason = reason
        @tenant = tenant
        @params = params.to_h.with_indifferent_access
        @values = {}
      end

      # @return [Array<Hash>] the submit options offered right now
      def available_submits
        self.class.submits.select { |option| option[:condition].nil? || instance_exec(&option[:condition]) }
      end

      def email_available? = Lucid::Backoffice.configuration.email_available?

      # Coerces the params into the declared fields.
      # @raise [ArgumentError] a value is invalid or a required field is missing
      def prepare!
        self.class.fields.each do |name, field|
          value = field.coerce(params[name], self)
          value = record.public_send(name) if value.nil? && record.respond_to?(name) && !field.required
          raise ArgumentError, "#{name} is required" if value.nil? && field.required

          @values[name] = value
        end
        self
      end

      # @return [Hash{Symbol => Object}] what the form starts with: the declared default, or the current
      #   value of the record attribute named like the field. A field over a column that is not public starts as
      #   {Field::LOCKED}, never with the value, whether or not the operator has a Reveal. A required field
      #   must still be submitted.
      def initial_values
        locked = locked_names
        self.class.fields.to_h do |name, field|
          next [name, Field::LOCKED] if locked.include?(name)

          current = record.public_send(name) if record.respond_to?(name)
          [name, current.nil? ? field.default_for(self) : current]
        end
      end

      # @return [Array<Symbol>] the fields over a column of the record's table that is not public. Without a
      #   record (collection, tenant or global action) nothing is locked.
      def locked_names
        table = self.class.target
        return [] if record.nil? || table.nil? || %w[tenant global].include?(table)

        self.class.fields.keys.select do |name|
          record.respond_to?(name) && (hidden_column?(table, name) || Classification.category_for(table, name) != Classification::PUBLIC)
        end
      end

      # @return [Symbol, nil] +:read+ when unlocking reads the current value (a masked column), +:write+ when it
      #   only lets a new one be written (a hidden column), +nil+ when the field is not locked
      def unlock_mode(name)
        return nil unless locked_names.include?(name.to_sym)

        hidden_column?(self.class.target, name) ? :write : :read
      end

      # @return [String, nil] the category the operator needs to reveal to unlock the field for reading
      def unlock_category(name)
        Classification.category_for(self.class.target, name) if unlock_mode(name) == :read
      end

      def hidden_column?(table, name)
        name.to_s.match?(Lucid::Backoffice.configuration.secret_columns) || Resource.for(table)&.hidden&.include?(name.to_s) || false
      end

      private def unlock_accepted?(name, opened, submitted, operator)
        return false unless opened.include?(name.to_s)

        case unlock_mode(name)
        when :write then submitted.present?
        when :read then operator && Authorization.allowed?(operator, :reveal, { tenant: tenant, category: unlock_category(name) })
        end
      end

      # Params with the locked fields replaced by the record's current value, read on the server. A locked field
      # keeps what was submitted only when it came listed in +unlocked+, the operator may reveal its category
      # and, for a hidden column, the new value is not blank.
      def with_locked_current(params, unlocked: [], operator: nil)
        opened = Array(unlocked).map(&:to_s)
        locked_names.each_with_object(params.to_h.with_indifferent_access) do |name, result|
          result[name] = record.public_send(name) unless unlock_accepted?(name, opened, result[name], operator)
        end
      end

      # @return [Boolean] false when an +only_if+ fails: the action is not offered at all
      def visible?
        self.class.conditions.all? { |condition| instance_exec(&condition[:block]) }
      end

      # @return [String, nil] why the action cannot run now, nil when it can
      def unavailable_reason
        self.class.conditions.each do |condition|
          return (condition[:reason] || "not available") unless instance_exec(&condition[:block])
        end
        self.class.guards.each { |guard| return guard[:message] if instance_exec(&guard[:block]) }
        nil
      end

      # @return [Preview] custom +preview+ block, or the default: each field named like an attribute of the record
      def build_preview
        preview = Preview.new
        if self.class.preview
          instance_exec(preview, &self.class.preview)
        else
          self.class.fields.each_key do |name|
            preview.change(record, name, to: values[name]) if record.respond_to?(name) && record.respond_to?(:class) && record.class.respond_to?(:table_name)
          end
        end
        preview
      end

      def execute
        command = self.class.perform_with
        return instance_exec(&self.class.perform) unless command

        attributes = values.dup
        names = command.respond_to?(:attribute_names) ? command.attribute_names : []
        attributes[:record] = record if names.include?(:record)
        attributes[:tenant] = tenant if names.include?(:tenant)
        attributes[:submit] = submitted if names.include?(:submit)
        command.call(**attributes)
      end

      # @return [String, nil] the one-time secret of this run
      def secret_for(value)
        return nil unless self.class.secret

        instance_exec(value, &self.class.secret).presence&.to_s
      end

      def result_message(value)
        self.class.result ? instance_exec(value, &self.class.result) : nil
      end

      def redirect_url(value)
        self.class.redirect_to ? instance_exec(value, &self.class.redirect_to) : nil
      end

      # Used by +result { notice "..." }+.
      def notice(text) = text
    end
  end
end
