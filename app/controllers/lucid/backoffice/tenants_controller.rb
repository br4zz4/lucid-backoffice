module Lucid
  module Backoffice
    class TenantsController < ApplicationController
      def show
        authorize!(:view_tenant, { tenant: current_tenant })
        @tenant = current_tenant
        @health = tenancy.health(@tenant)
        @sections = Registry.sections.select { |section| allowed?(section.permission, { tenant: @tenant }) }
      end
    end
  end
end
