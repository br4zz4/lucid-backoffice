module Lucid
  module Backoffice
    # Base of every back office screen. Apps inherit from it to add their own screens inside the same
    # layout, authentication, authorization and activity context.
    class ApplicationController < ActionController::Base
      include Lucid::Backoffice::Context

      protect_from_forgery with: :exception
      layout -> { Lucid::Backoffice.configuration.layout || "lucid/backoffice/application" }

      before_action :lucid_backoffice_authenticate

      rescue_from Lucid::Backoffice::Error::Forbidden do
        render plain: "Forbidden", status: :forbidden
      end
      rescue_from Lucid::Backoffice::Records::NotFound, ActiveRecord::RecordNotFound do
        render plain: "Not found", status: :not_found
      end

      helper_method :current_operator, :allowed?, :lucid_backoffice_menu, :tenancy, :current_tenant, :lb_routes,
                    :lb_root_path, :lb_context_crumbs, :current_reveals, :context_label, :context_schema, :context_tables, :context_switch_tenants, :table_link, :lb_current?

      private

      def lucid_backoffice_authenticate
        Lucid::Backoffice.configuration.authenticate.call(self)
      end

      def current_operator
        @current_operator ||= Lucid::Backoffice.configuration.current_operator.call(self)
      end

      def lb_routes
        Lucid::Backoffice::Engine.routes.url_helpers
      end

      def tenancy
        Lucid::Backoffice::Tenancy.adapter
      end

      def allowed?(permission, context = {})
        Lucid::Backoffice::Authorization.allowed?(current_operator, permission, context)
      end

      def authorize!(permission, context = {})
        Lucid::Backoffice::Authorization.authorize!(current_operator, permission, context)
      end

      def lucid_backoffice_menu
        Lucid::Backoffice::Registry.menu_items.select { |item| allowed?(item.permission) }
      end

      def lb_root_path
        lb_routes.root_path.sub(%r{/\z}, "").presence || "/"
      end

      def current_reveals
        @current_reveals ||= Reveal.active.where(operator_type: current_operator.class.name, operator_id: current_operator.id,
                                                 tenant_identifier: Reveal.tenant_identifier(current_tenant)).to_a
      end

      def lb_context_crumbs
        shared = Lucid::Backoffice.configuration.terms.fetch(:shared, I18n.t("lucid_backoffice.shared"))
        crumbs = [[shared, lb_root_path]]
        crumbs << [tenancy.label(current_tenant), lb_routes.tenant_path(tenant_id: tenancy.identifier(current_tenant))] if current_tenant
        crumbs
      end

      def context_label
        return tenancy.label(current_tenant) if current_tenant

        Lucid::Backoffice.configuration.terms.fetch(:shared, I18n.t("lucid_backoffice.shared"))
      end

      def context_schema
        tenancy.schema_for(current_tenant)
      end

      def context_tables
        return [] unless allowed?(:browse, { tenant: current_tenant })

        Catalog.tables(context_schema)
      end

      def context_switch_tenants
        tenancy.tenants.select { |tenant| allowed?(:view_tenant, { tenant: tenant }) }
      end

      def table_link(table)
        return lb_routes.table_path(table: table) unless current_tenant

        lb_routes.tenant_table_path(tenant_id: tenancy.identifier(current_tenant), table: table)
      end

      def lb_current?(path, prefix: false)
        prefix ? request.path.start_with?(path) : request.path.sub(%r{/\z}, "") == path
      end

      def current_tenant
        return @current_tenant if defined?(@current_tenant)

        @current_tenant = params[:tenant_id] ? (tenancy.find(params[:tenant_id]) || raise(Lucid::Backoffice::Records::NotFound, "no tenant")) : nil
      end
    end
  end
end
