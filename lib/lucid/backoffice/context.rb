module Lucid
  module Backoffice
    # Include in a controller to fill {Current} before each action. The actor comes from
    # +config.current_actor+ (falling back to +config.current_operator+).
    module Context
      extend ActiveSupport::Concern

      included do
        before_action :lucid_backoffice_set_context
      end

      private

      def lucid_backoffice_set_context
        config = Lucid::Backoffice.configuration
        resolver = config.current_actor || config.current_operator
        Current.actor = resolver&.call(self)
        Current.request_id = request.request_id
        Current.ip_address = request.remote_ip
        Current.user_agent = request.user_agent
      end
    end
  end
end
