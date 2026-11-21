require "active_support"
require "active_support/core_ext"
require "active_record"

require "lucid/backoffice/version"
require "lucid/backoffice/errors"
require "lucid/backoffice/configuration"
require "lucid/backoffice/classification"
require "lucid/backoffice/mask"

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

      def reset_configuration!
        @configuration = Configuration.new
        Classification.reset!
      end
    end
  end
end
