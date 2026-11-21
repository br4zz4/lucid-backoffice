module Lucid
  module Backoffice
    class Engine < ::Rails::Engine
      isolate_namespace Lucid::Backoffice
      engine_name "lucid_backoffice"

      rake_tasks do
        load File.expand_path("../../tasks/lucid_backoffice.rake", __dir__)
      end
    end
  end
end
