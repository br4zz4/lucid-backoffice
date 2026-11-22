require "rails/generators"

module Lucid
  module Backoffice
    module Generators
      # Creates app/backoffice/actions/<name>.rb.
      #
      #   bin/rails g lucid:backoffice:action ChangeUserRole
      class ActionGenerator < ::Rails::Generators::NamedBase
        source_root File.expand_path("templates", __dir__)
        namespace "lucid:backoffice:action"
        desc "Creates a corrective action in app/backoffice/actions"

        def create_action
          template "action.rb.tt", File.join("app/backoffice/actions", class_path, "#{file_name}.rb")
        end
      end
    end
  end
end
