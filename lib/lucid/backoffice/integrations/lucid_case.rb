require "lucid/case"
require "lucid/backoffice"

module Lucid
  module Backoffice
    module Integrations
      # Records an activity event for every Lucid::Case Command, with nothing declared in the Command.
      # The event is written where the case event is born: inside the Command's transaction on success
      # (so a failing write undoes the Command), after the rollback on a typed failure or guard.
      #
      # A Command may define +activity_payload+ (a Hash of identifiers) to add to the event.
      module LucidCase
        module_function

        def install!
          observers = Lucid::Case.configuration.events.observers
          observers << method(:observe) unless observers.include?(method(:observe))
        end

        def observe(event:, command:, result:)
          return unless event.kind == :case

          records = records_in(event.input) + records_in(event.content)
          Activity.record(
            name: event.name,
            outcome: event.success? ? "ok" : event.type.to_s,
            subjects: records.uniq.map { |record| { "type" => record.class.name, "id" => record.id } },
            changed_fields: changed_fields(records),
            payload: command.respond_to?(:activity_payload) ? command.activity_payload : {}
          )
        end

        def records_in(values)
          Array(values.respond_to?(:values) ? values.values : values).flat_map { |value| value.is_a?(Array) ? value : [value] }
                                                                      .select { |value| value.is_a?(ActiveRecord::Base) && value.persisted? }
        end

        def changed_fields(records)
          records.flat_map { |record| record.saved_changes.keys }.uniq - %w[updated_at]
        end
      end
    end
  end
end

Lucid::Backoffice::Integrations::LucidCase.install!
