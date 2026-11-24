module Lucid
  module Backoffice
    # Whether the host app can send email at all, read from its ActionMailer settings. The gem never
    # knows which provider the app uses; an app that knows better sets +config.email_available+.
    module Mail
      LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

      module_function

      def available?
        return false unless defined?(ActionMailer::Base)
        return false unless ActionMailer::Base.perform_deliveries

        method = ActionMailer::Base.delivery_method
        return smtp_configured? if method == :smtp

        ActionMailer::Base.delivery_methods.key?(method)
      end

      def smtp_configured?
        address = ActionMailer::Base.smtp_settings.to_h[:address].to_s.strip
        !address.empty? && !LOCAL_HOSTS.include?(address)
      end
    end
  end
end
