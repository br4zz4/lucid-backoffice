module Lucid
  module Backoffice
    # Base class of every error raised by Lucid::Backoffice itself.
    class Error < StandardError
      # A configuration value is missing or inconsistent; raised at boot, naming the key.
      class ConfigurationConflict < Error; end
    end
  end
end
