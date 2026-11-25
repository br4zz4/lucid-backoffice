module Lucid
  module Backoffice
    class Action
      # One input of an Action. The value is validated and coerced by its type.
      Field = Data.define(:name, :type, :choices, :default, :of, :scope, :partial, :required, :label) do
        def initialize(label: nil, **attributes) = super

        def title = (label.respond_to?(:call) ? label.call : label).presence || name.to_s.humanize

        TYPES = %i[string text integer boolean date select record].freeze

        # @return [Object] the coerced value
        # @raise [ArgumentError] the value is not valid for the type
        def coerce(value, action)
          return default_for(action) if value.nil? || value == ""

          case type
          when :integer, :record then Integer(value.to_s, exception: false) || raise(ArgumentError, "#{name} must be an integer")
          when :boolean then ActiveModel::Type::Boolean.new.cast(value) || false
          when :date then Date.iso8601(value.to_s)
          when :select
            allowed = Array(choices.respond_to?(:call) ? action.instance_exec(&choices) : choices).map(&:to_s)
            raise ArgumentError, "#{name} is not one of the choices" unless allowed.include?(value.to_s)

            value.to_s
          else value.to_s
          end
        rescue Date::Error
          raise ArgumentError, "#{name} must be a date"
        end

        def default_for(action)
          default.respond_to?(:call) ? action.instance_exec(&default) : default
        end
      end

      Field.const_set(:LOCKED, Object.new.tap { |sentinel| sentinel.define_singleton_method(:inspect) { "LOCKED" } }.freeze)
    end
  end
end
