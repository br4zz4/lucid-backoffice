module Lucid
  module Backoffice
    # Include in the ApplicationController of the app. During an impersonation every request is read-only,
    # recorded as a page view, attributed to the operator, and ends when the time is up.
    module ImpersonationGuard
      extend ActiveSupport::Concern

      SAFE_VERBS = %w[GET HEAD].freeze

      included do
        helper Lucid::Backoffice::ImpersonationHelper
        prepend_before_action :lucid_backoffice_impersonation_guard
      end

      private

      def lucid_backoffice_impersonation_guard
        id = session[:lucid_backoffice_impersonation_id]
        return unless id

        impersonation = Impersonation.find_by(id: id)
        return lucid_backoffice_impersonation_over(impersonation) unless impersonation&.active?

        Current.impersonation_id = impersonation.id
        Current.actor = impersonation.operator_record
        Current.tenant_identifier ||= impersonation.tenant_identifier
        @lucid_backoffice_impersonation = impersonation
        return lucid_backoffice_read_only_denied unless lucid_backoffice_request_allowed?

        lucid_backoffice_record_page_view if SAFE_VERBS.include?(request.request_method)
      end

      def lucid_backoffice_request_allowed?
        return true if SAFE_VERBS.include?(request.request_method)

        Lucid::Backoffice.configuration.impersonation.read_only_except.any? { |entry| entry.to_s == request.path }
      end

      def lucid_backoffice_read_only_denied
        render plain: I18n.t("lucid_backoffice.impersonation_read_only", default: "Impersonation is read-only"), status: :forbidden
      end

      def lucid_backoffice_record_page_view
        payload = { controller: controller_path.gsub(%r{[^a-z_./]}, ""), action: action_name.gsub(/[^a-z_]/, "") }
        payload[:id] = Integer(params[:id].to_s, exception: false) if params[:id]
        Activity.record(name: "backoffice.impersonation.page_view", payload: payload.compact)
      end

      def lucid_backoffice_impersonation_over(impersonation)
        impersonation&.end!(reason: "expired")
        config = Lucid::Backoffice.configuration.impersonation
        config.sign_out&.call(self)
        reset_session
        redirect_to(config.return_url&.call(impersonation) || "/", allow_other_host: true)
      end
    end
  end
end
