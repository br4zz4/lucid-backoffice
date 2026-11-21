require "rails/railtie"

module Lucid
  module Backoffice
    class Railtie < Rails::Railtie
      rake_tasks do
        load File.expand_path("../../tasks/lucid_backoffice.rake", __dir__)
      end
    end
  end
end
