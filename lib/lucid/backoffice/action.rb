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
      Result = Data.define(:status, :message, :value) do
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

        def on(target = nil)
          target ? @target = target.to_s : @target
        end
        alias_method :target, :on

        def label(text = nil)
          text ? @label = text : (@label || key.humanize)
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

        def conditions = (@conditions ||= [])
        def guards = (@guards ||= [])

        def preview(&block)
          block ? @preview = block : @preview
        end

        def perform(&block)
          block ? @perform = block : @perform
        end

        def result(&block)
          block ? @result = block : @result
        end
      end

      attr_reader :record, :tenant, :params, :values

      def initialize(record: nil, tenant: nil, params: {})
        @record = record
        @tenant = tenant
        @params = params.to_h.with_indifferent_access
        @values = {}
      end

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
      #   value of the record attribute named like the field. A required field must still be submitted.
      def initial_values
        self.class.fields.to_h do |name, field|
          current = record.public_send(name) if record.respond_to?(name)
          [name, current.nil? ? field.default_for(self) : current]
        end
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
        instance_exec(&self.class.perform)
      end

      def result_message(value)
        self.class.result ? instance_exec(value, &self.class.result) : nil
      end

      # Used by +result { notice "..." }+.
      def notice(text) = text
    end
  end
end
