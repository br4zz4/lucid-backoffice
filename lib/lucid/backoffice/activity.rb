require "lucid/backoffice/activity/event"
require "lucid/backoffice/activity/tracker"
require "lucid/backoffice/activity/purge"

module Lucid
  module Backoffice
    # The activity trail: an {Event} per action that writes, recorded in the same transaction.
    module Activity
      SYSTEM = "System".freeze

      module_function

      # Writes one event with the actor and request taken from {Current}.
      #
      # @return [Event]
      # @raise [ActiveRecord::RecordInvalid] the payload holds something that is not an identifier
      def record(name:, outcome: "ok", subjects: [], changed_fields: [], payload: {}, reason: nil, actor: Current.actor)
        attributes = {
          name: name.to_s, outcome: outcome.to_s,
          actor_type: actor ? actor.class.name : SYSTEM, actor_id: actor.respond_to?(:id) ? actor.id : nil,
          tenant_identifier: Current.tenant_identifier&.to_s,
          subjects: subjects, changed_fields: changed_fields, payload: payload,
          reason: reason || Current.reason, request_id: Current.request_id,
          ip_address: Current.ip_address, user_agent: Current.user_agent, occurred_at: Time.current
        }
        attributes[:impersonation_id] = Current.impersonation_id if Event.column_names.include?("impersonation_id")
        Event.create!(attributes)
      end

      # Runs the block in a transaction and records the event in it: it exists if and only if the
      # writes do. A raised error records nothing. A result that answers +failure?+ with true undoes
      # the writes and records the event with the failure type as its outcome, unless +undo_on_failure+ is
      # false (the block already undid its own writes, as a Lucid::Case Command does).
      #
      # @yieldparam tracker [Tracker] to declare subjects and payload
      # @return the value of the block
      def track(name, reason: nil, undo_on_failure: true)
        tracker = Tracker.new
        value = nil
        failed = false
        ActiveRecord::Base.transaction(requires_new: true) do
          value = yield tracker
          if value.respond_to?(:failure?) && value.failure?
            if undo_on_failure
              failed = true
              raise ActiveRecord::Rollback
            end

            record(name: name, outcome: value.type.to_s, subjects: tracker.subjects, payload: tracker.payload, reason: reason)
          else
            record(name: name, subjects: tracker.subjects, changed_fields: tracker.changed_fields, payload: tracker.payload, reason: reason)
          end
        end
        record(name: name, outcome: value.type.to_s, payload: tracker.payload, reason: reason) if failed
        value
      end
    end
  end
end
