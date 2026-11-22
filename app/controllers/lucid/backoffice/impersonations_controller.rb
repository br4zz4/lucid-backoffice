module Lucid
  module Backoffice
    # Runs on the host of the tenant, where there is no operator session: the one-time token is the
    # credential. Mount it with the generator (`lucid_backoffice/impersonation/enter` and `.../impersonation`).
    class ImpersonationsController < ActionController::Base
      def enter
        config = Lucid::Backoffice.configuration.impersonation
        tenant = config.tenant_for_request&.call(request)
        impersonation = Impersonation.enter(params[:token].to_s, tenant_identifier: tenant)
        user = config.find_user.call(tenant, impersonation.user_id) or raise Records::NotFound, "no such user"
        reset_session
        session[:lucid_backoffice_impersonation_id] = impersonation.id
        config.sign_in.call(self, user)
        Current.impersonation_id = impersonation.id
        Current.actor = impersonation.operator_record
        Activity.record(name: "backoffice.impersonation.enter", reason: impersonation.reason, actor: impersonation.operator_record)
        redirect_to "/"
      rescue Records::NotFound
        render plain: "Not found", status: :not_found
      end

      def destroy
        impersonation = Impersonation.find_by(id: session[:lucid_backoffice_impersonation_id])
        Current.impersonation_id = impersonation&.id
        impersonation&.end!(reason: "manual")
        Lucid::Backoffice.configuration.impersonation.sign_out&.call(self)
        reset_session
        redirect_to(Lucid::Backoffice.configuration.impersonation.return_url&.call(impersonation) || "/", allow_other_host: true)
      end
    end
  end
end
