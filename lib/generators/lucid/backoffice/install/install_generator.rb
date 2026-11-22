require "rails/generators"
require "rails/generators/active_record"

module Lucid
  module Backoffice
    module Generators
      # Installs the back office: initializer, the two migrations, an example classification and the mount.
      #
      #   bin/rails g lucid:backoffice:install
      class InstallGenerator < ::Rails::Generators::Base
        include ::Rails::Generators::Migration

        source_root File.expand_path("templates", __dir__)
        namespace "lucid:backoffice:install"
        desc "Creates the initializer, migrations, config/data_classification.yml and mounts the engine"

        def self.next_migration_number(dirname)
          ::ActiveRecord::Generators::Base.next_migration_number(dirname)
        end

        def create_initializer
          template "lucid_backoffice.rb.tt", "config/initializers/lucid_backoffice.rb"
        end

        def create_migrations
          migration_template "create_lucid_backoffice_activity_events.rb.tt", "db/migrate/create_lucid_backoffice_activity_events.rb"
          migration_template "create_lucid_backoffice_reveals.rb.tt", "db/migrate/create_lucid_backoffice_reveals.rb"
        end

        def create_classification
          template "data_classification.yml.tt", "config/data_classification.yml"
        end

        def mount_engine
          route 'mount Lucid::Backoffice::Engine => "/backoffice"'
        end
      end
    end
  end
end
