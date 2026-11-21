require "lucid/tenancy"
require "lucid/backoffice"
require "lucid/backoffice/tenancy"

module Lucid
  module Backoffice
    module Adapters
      # Reads tenants and their schemas through Lucid::Tenancy's public API only.
      class LucidTenancy
        def tenants
          Lucid::Tenancy.tenant_class.all.sort_by { |tenant| identifier(tenant).to_s }
        end

        def find(identifier)
          Lucid::Tenancy.tenant_class.find_by_tenancy_identifier(identifier)
        end

        def identifier(tenant)
          tenant.tenant_identifier.to_s
        end

        def label(tenant)
          tenant.respond_to?(:name) ? tenant.name.to_s : identifier(tenant)
        end

        def health(tenant)
          Lucid::Tenancy.health(tenant)
        end

        def multi_tenant? = true

        def shared_schema
          Lucid::Tenancy.configuration.shared_schema
        end

        def schema_for(tenant)
          tenant ? tenant.schema_name : shared_schema
        end
      end
    end
  end
end
