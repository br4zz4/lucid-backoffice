module Lucid
  module Backoffice
    # Base class of every error raised by Lucid::Backoffice itself.
    class Error < StandardError
      # A configuration value is missing or inconsistent; raised at boot, naming the key.
      class ConfigurationConflict < Error; end

      # The operator may not do this (the default authorize denies everything).
      class Forbidden < Error; end
    end
  end
end
