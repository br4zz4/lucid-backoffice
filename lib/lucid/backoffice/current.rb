module Lucid
  module Backoffice
    # Who is acting and from where, set once per request or job and cleared at the end.
    class Current < ActiveSupport::CurrentAttributes
      attribute :actor, :tenant_identifier, :request_id, :ip_address, :user_agent, :reason, :impersonation_id, :revealed_categories
    end
  end
end
