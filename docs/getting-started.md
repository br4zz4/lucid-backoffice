# Getting started

1. Add the gem: `gem "lucid-backoffice", github: "br4zz4/lucid-backoffice", tag: "v0.1.0"`.
2. `bin/rails g lucid:backoffice:install` creates the initializer, the two migrations (activity events and reveals), `config/data_classification.yml` and mounts the engine at `/backoffice`. Run `bin/rails db:migrate`.
3. Fill `config.current_operator`, `config.authenticate` and `config.authorize` in the initializer. Until `authorize` answers, every screen is a 403.
4. Classify the columns you want visible or revealable in `config/data_classification.yml`.

With `lucid-tenancy` the generated migrations declare `tenancy :shared`.
