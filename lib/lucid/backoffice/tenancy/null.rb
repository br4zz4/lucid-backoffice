module Lucid
  module Backoffice
    module Tenancy
      # Single-tenant apps: no tenants, everything lives in the current schema.
      class Null
        def tenants = []
        def find(_identifier) = nil
        def identifier(_tenant) = nil
        def label(_tenant) = nil
        def health(_tenant) = nil
        def multi_tenant? = false

        def shared_schema
          ActiveRecord::Base.lease_connection.current_schema
        end

        def schema_for(_tenant)
          shared_schema
        end
      end
    end
  end
end
