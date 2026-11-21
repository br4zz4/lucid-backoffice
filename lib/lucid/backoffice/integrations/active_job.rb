require "active_job"
require "lucid/backoffice"

module Lucid
  module Backoffice
    module Integrations
      # Carries the actor and request id of whoever enqueued a job into its run, so the events a job
      # records name the right actor. A job enqueued with no actor runs as System.
      module ActiveJob
        KEY = "lucid_backoffice".freeze

        def serialize
          super.merge(KEY => { "actor" => global_id(Current.actor), "request_id" => Current.request_id, "tenant" => Current.tenant_identifier })
        end

        def deserialize(job_data)
          super
          @lucid_backoffice_context = job_data[KEY] || {}
        end

        def perform_now
          context = @lucid_backoffice_context || {}
          Current.set(actor: locate(context["actor"]), request_id: context["request_id"], tenant_identifier: context["tenant"]) { super }
        end

        private

        def global_id(actor)
          actor.respond_to?(:to_global_id) ? actor.to_global_id.to_s : nil
        end

        def locate(id)
          id && GlobalID::Locator.locate(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
      end
    end
  end
end

ActiveJob::Base.prepend(Lucid::Backoffice::Integrations::ActiveJob)
