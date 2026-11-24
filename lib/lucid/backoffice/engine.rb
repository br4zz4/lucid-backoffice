module Lucid
  module Backoffice
    class Engine < ::Rails::Engine
      isolate_namespace Lucid::Backoffice
      engine_name "lucid_backoffice"

      config.to_prepare do
        Lucid::Backoffice::Action.reset!
        Lucid::Backoffice::Resource.reset!
        dir = Rails.root.join("app/backoffice")
        Rails.autoloaders.main.eager_load_dir(dir.to_s) if dir.exist? && Rails.autoloaders.main.respond_to?(:eager_load_dir)
      end

      initializer "lucid_backoffice.filter_parameters" do |app|
        app.config.filter_parameters |= %i[criteria filter_value filter fields]
      end

      rake_tasks do
        load File.expand_path("../../tasks/lucid_backoffice.rake", __dir__)
      end
    end
  end
end
