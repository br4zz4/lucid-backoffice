module Lucid
  module Backoffice
    module Activity
      # Collects what a tracked block touched.
      class Tracker
        attr_reader :subjects, :changed_fields, :payload

        def initialize
          @subjects = []
          @changed_fields = []
          @payload = {}
        end

        # Declares a record the block acted on: stores its type and id and the names (never the values)
        # of the attributes it just changed.
        def subject(record)
          @subjects << { "type" => record.class.name, "id" => record.id }
          @changed_fields |= record.saved_changes.keys - %w[updated_at] if record.respond_to?(:saved_changes)
          record
        end

        def payload(values = nil)
          return @payload if values.nil?

          @payload = @payload.merge(values.stringify_keys)
        end
      end
    end
  end
end
