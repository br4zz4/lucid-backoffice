module Lucid
  module Backoffice
    # Asks the host app whether an operator may do something. The back office defines no roles: only
    # the permissions it asks about, answered by +config.authorize+, which denies everything by default.
    module Authorization
      PERMISSIONS = %i[view_dashboard view_tenant browse reveal view_activity].freeze

      module_function

      def allowed?(operator, permission, context = {})
        return false unless operator

        Lucid::Backoffice.configuration.authorize.call(operator, permission.to_sym, context) ? true : false
      end

      # @raise [Error::Forbidden]
      def authorize!(operator, permission, context = {})
        return true if allowed?(operator, permission, context)

        raise Error::Forbidden, "not allowed to #{permission}"
      end
    end
  end
end
