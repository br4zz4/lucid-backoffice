# Lucid::Backoffice

An operation panel for Rails apps. Operators browse the app's data without declaring anything, and **every column is masked** unless it is classified `public` or an operator reveals its category with a reason. What they see and do is recorded.

```ruby
# config/initializers/lucid_backoffice.rb
Lucid::Backoffice.configure do |config|
  config.current_operator = ->(controller) { controller.current_user }
  config.authenticate = ->(controller) { controller.authenticate_user! }
  config.authorize = ->(operator, permission, _context) { operator.admin? && %i[view_dashboard browse reveal].include?(permission) }
  config.classification_path = Rails.root.join("config/data_classification.yml").to_s
end
```

```yaml
# config/data_classification.yml
users:
  email: contact
  name: contact
  role: public
```

Open `/backoffice/data/users`: `role` is in the clear, `email` and `name` show `•••••`, and a column nobody classified shows `•••••` too. An operator with the `reveal` permission reveals `contact` for 15 minutes by giving a reason; the reveal and the reason are recorded.

It depends only on `activerecord` and `railties`. Devise, CanCanCan, `lucid-tenancy` and `lucid-case` are never required: they plug in through configuration and optional adapters.

```sh
bin/rails g lucid:backoffice:install
bin/rails db:migrate
```

## Guides

- [Getting started](docs/getting-started.md)
- [Configuration](docs/configuration.md)
- [Resources](docs/resources.md)
- [Classification](docs/classification.md)
- [Masking and reveals](docs/masking-and-reveals.md)
- [Activity trail](docs/activity.md)
- [Tenancy](docs/tenancy.md)
- [Plugins and screens](docs/plugins.md)
- [Customization](docs/customization.md)
- [Security](docs/security.md)
- [Testing](docs/testing.md)

## Requirements

Ruby 3.2+, Rails 7.2 to 8, PostgreSQL. MIT license.
