require_relative "lib/lucid/backoffice/version"

Gem::Specification.new do |spec|
  spec.name = "lucid-backoffice"
  spec.version = Lucid::Backoffice::VERSION
  spec.authors = ["Brazza Labs"]
  spec.summary = "Operation panel for Rails apps: masked-by-default data browsing, reveals, activity trail and corrective actions"
  spec.description = "Lucid::Backoffice is a Rails engine that gives operators a read-only panel over the app's data, with every column " \
                     "masked unless classified public or revealed with a reason, plus an activity trail. Authentication, roles, " \
                     "tenancy and use cases are integrated through configuration and optional adapters."
  spec.homepage = "https://github.com/br4zz4/lucid-backoffice"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "app/**/*", "config/**/*", "docs/**/*.md", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.2", "< 9.0"
  spec.add_dependency "railties", ">= 7.2", "< 9.0"
end
