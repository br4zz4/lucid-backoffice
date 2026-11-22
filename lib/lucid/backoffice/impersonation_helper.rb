module Lucid
  module Backoffice
    # Shows the banner of an active impersonation. Call it in the layout of your app.
    module ImpersonationHelper
      def lucid_backoffice_impersonation_banner
        impersonation = @lucid_backoffice_impersonation
        return unless impersonation

        render partial: "lucid/backoffice/impersonation/banner", locals: { impersonation: impersonation }
      end
    end
  end
end
