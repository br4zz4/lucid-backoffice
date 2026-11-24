require "active_support"
require "active_support/core_ext"
require "active_record"

require "lucid/backoffice/version"
require "lucid/backoffice/errors"
require "lucid/backoffice/theme"
require "lucid/backoffice/configuration"
require "lucid/backoffice/classification"
require "lucid/backoffice/mask"
require "lucid/backoffice/current"
require "lucid/backoffice/context"
require "lucid/backoffice/activity"
require "lucid/backoffice/tenancy"
require "lucid/backoffice/catalog"
require "lucid/backoffice/records"
require "lucid/backoffice/records/query"
require "lucid/backoffice/resource"
require "lucid/backoffice/authorization"
require "lucid/backoffice/reveal"
require "lucid/backoffice/panel_activity"
require "lucid/backoffice/registry"
require "lucid/backoffice/impersonation"
require "lucid/backoffice/impersonation_guard"
require "lucid/backoffice/impersonation_mask"
require "lucid/backoffice/impersonation_helper"
require "lucid/backoffice/action"
require "action_controller"
require "action_view"
require "rails/engine"
require "lucid/backoffice/engine"

module Lucid
  # An operation panel for Rails apps, masked by default.
  module Backoffice
    class << self
      # @return [Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      # @yieldparam config [Configuration]
      def configure
        yield configuration
        configuration.validate!
        Classification.load!
        configuration
      end

      # @return [Boolean] whether the current request runs inside an impersonation
      def impersonating?
        Current.impersonation_id.present?
      end

      # Registers menu items, cards, tenant sections and permissions. The app and plugins use the same API.
      def register(name, &block)
        Registry.register(name, &block)
      end

      def reset_configuration!
        @configuration = Configuration.new
        Classification.reset!
        Tenancy.reset!
        Resource.reset!
        Registry.reset!
        Action.reset!
      end
    end
  end
end
