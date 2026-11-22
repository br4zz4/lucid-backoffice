require "rails/generators"
require "rails/generators/active_record"

module Lucid
  module Backoffice
    module Generators
      # Adds the impersonation table and the two routes served on the host of the tenant.
      #
      #   bin/rails g lucid:backoffice:impersonation
      class ImpersonationGenerator < ::Rails::Generators::Base
        include ::Rails::Generators::Migration

        source_root File.expand_path("../install/templates", __dir__)
        namespace "lucid:backoffice:impersonation"
        desc "Creates the impersonations migration and the entry routes"

        def self.next_migration_number(dirname)
          ::ActiveRecord::Generators::Base.next_migration_number(dirname)
        end

        def create_impersonations_migration
          migration_template "create_lucid_backoffice_impersonations.rb.tt", "db/migrate/create_lucid_backoffice_impersonations.rb"
        end

        def add_routes
          route 'get "lucid_backoffice/impersonation/enter", to: "lucid/backoffice/impersonations#enter"'
          route 'delete "lucid_backoffice/impersonation", to: "lucid/backoffice/impersonations#destroy"'
        end

        def show_next_steps
          say "Next: set config.impersonation (find_user, sign_in, sign_out, entry_url, return_url), include " \
              "Lucid::Backoffice::ImpersonationGuard in your ApplicationController and Lucid::Backoffice::ImpersonationMask in " \
              "ApplicationRecord, and render lucid_backoffice_impersonation_banner in your layout."
        end
      end
    end
  end
end
