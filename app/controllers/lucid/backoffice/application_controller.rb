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

      helper_method :current_operator, :allowed?, :lucid_backoffice_menu, :tenancy, :current_tenant, :lb_routes

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

      def current_tenant
        return @current_tenant if defined?(@current_tenant)

        @current_tenant = params[:tenant_id] ? (tenancy.find(params[:tenant_id]) || raise(Lucid::Backoffice::Records::NotFound, "no tenant")) : nil
      end
    end
  end
end
