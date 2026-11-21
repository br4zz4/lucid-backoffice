module Lucid
  module Backoffice
    class RevealsController < ApplicationController
      def create
        tenant = params[:tenant_id].presence && (tenancy.find(params[:tenant_id]) || raise(Records::NotFound, "no tenant"))
        Current.tenant_identifier = Reveal.tenant_identifier(tenant)
        Reveal.grant(operator: current_operator, tenant: tenant, category: params[:category], reason: params[:reason])
        redirect_back fallback_location: lucid_backoffice_root_path, notice: I18n.t("lucid_backoffice.revealed")
      rescue ActiveRecord::RecordInvalid => e
        redirect_back fallback_location: lucid_backoffice_root_path, alert: e.record.errors.full_messages.to_sentence
      end

      def destroy
        reveal = Reveal.find(params[:id])
        Current.tenant_identifier = reveal.tenant_identifier
        Reveal.revoke(reveal, operator: current_operator)
        redirect_back fallback_location: lucid_backoffice_root_path, notice: I18n.t("lucid_backoffice.revoked")
      end

      private

      def lucid_backoffice_root_path
        Lucid::Backoffice::Engine.routes.url_helpers.root_path
      end
    end
  end
end
