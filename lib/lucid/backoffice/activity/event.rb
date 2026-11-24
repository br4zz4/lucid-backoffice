module Lucid
  module Backoffice
    module Activity
      # An immutable record of who did or tried what. It carries identifiers and attribute names,
      # never the values of personal data.
      class Event < ActiveRecord::Base
        self.table_name = "lucid_backoffice_activity_events"

        TOKEN = %r{\A[a-z_./]{1,100}\z}

        validates :name, :outcome, :actor_type, :occurred_at, presence: true
        validate :payload_has_only_identifiers

        before_destroy { raise ActiveRecord::ReadOnlyRecord, "activity events cannot be destroyed" }

        def readonly?
          persisted? || super
        end

        # @return [Boolean] whether +value+ may be stored in a payload
        def self.identifier?(value)
          case value
          when nil, true, false, Integer then true
          when Array then value.all?(Integer) || value.all? { |item| item.is_a?(String) && item.match?(TOKEN) }
          when String then value.match?(TOKEN)
          else false
          end
        end

        private

        def payload_has_only_identifiers
          (payload.is_a?(Hash) ? payload : {}).each do |key, value|
            errors.add(:payload, "#{key} holds a value that is not an identifier") unless self.class.identifier?(value)
          end
        end
      end
    end
  end
end
