module Lucid
  module Backoffice
    class TenantsController < ApplicationController
      def show
        authorize!(:view_tenant, { tenant: current_tenant })
        @tenant = current_tenant
        @health = tenancy.health(@tenant)
        @sections = Registry.sections.select { |section| allowed?(section.permission, { tenant: @tenant }) }
        @reveals = Reveal.active.where(operator_type: current_operator.class.name, operator_id: current_operator.id,
                                       tenant_identifier: tenancy.identifier(@tenant))
      end
    end
  end
end
