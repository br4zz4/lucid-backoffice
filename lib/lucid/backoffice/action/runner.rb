module Lucid
  module Backoffice
    class Action
      # Runs an action: authorizes, checks availability, validates, compares the state with the preview,
      # then performs inside a tracked transaction with the reason.
      module Runner
        module_function

        # @param action_class [Class<Action>]
        # @param snapshot [String] the digest shown with the preview
        # @param confirmation [String] what the operator typed for a `danger :high` action
        def call(action_class, operator:, reason:, snapshot:, record: nil, tenant: nil, params: {}, confirmation: nil, revealed: [])
          context = { tenant: tenant, record: record, action: action_class.key }
          return failed(:forbidden, "not allowed") unless Authorization.allowed?(operator, action_class.permission, context)

          action = action_class.new(record: record, tenant: tenant, params: params, reason: reason&.to_s&.strip)
          action = action_class.new(record: record, tenant: tenant, reason: reason&.to_s&.strip,
                                    params: action.with_locked_current(params, revealed: revealed))
          reason = reason.to_s.strip
          minimum = Lucid::Backoffice.configuration.reveal_reason_min
          return failed(:invalid, "reason must have at least #{minimum} characters") if reason.length < minimum
          return failed(:unavailable, action.unavailable_reason) if action.unavailable_reason

          begin
            action.prepare!
          rescue ArgumentError => e
            return failed(:invalid, e.message)
          end
          return failed(:invalid, "confirmation does not match") unless confirmed?(action_class, record, tenant, confirmation)
          return failed(:stale, "the state changed, review the preview") unless action.build_preview.snapshot == snapshot

          perform(action, action_class, reason)
        end

        def perform(action, action_class, reason)
          name = "backoffice.action.#{action_class.key}"
          value = nil
          if action_class.transaction
            value = Activity.track(name, reason: reason, undo_on_failure: !action_class.perform_with) { action.execute }
          else
            value = action.execute
            Activity.record(name: name, outcome: failure_of(value) || "ok", reason: reason)
          end
          type = failure_of(value)
          type ? Action::Result.new(status: :failed, message: failure_message(action_class, value, type), value: value) : Action::Result.new(status: :ok, message: action.result_message(value), value: value, redirect: action.redirect_url(value))
        end

        def failure_message(action_class, value, type)
          errors = begin
            value[:errors]
          rescue NameError, KeyError, NoMethodError, TypeError
            nil
          end
          return Array(errors).first.to_s if errors.present?

          I18n.t("lucid_backoffice.actions.#{action_class.key}.failures.#{type}", default: type.humanize)
        end

        def failure_of(value)
          value.respond_to?(:failure?) && value.failure? ? value.type.to_s : nil
        end

        def confirmed?(action_class, record, tenant, confirmation)
          return true unless action_class.danger == :high

          expected = tenant ? Tenancy.adapter.identifier(tenant) : record&.id
          expected.to_s != "" && confirmation.to_s == expected.to_s
        end

        def failed(status, message)
          Action::Result.new(status: status, message: message, value: nil)
        end
      end
    end
  end
end
