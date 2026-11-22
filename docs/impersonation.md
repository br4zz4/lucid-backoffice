# Impersonation

An operator sees the app as one of its users: read-only, masked, for `config.impersonation.duration` (30 minutes), with a mandatory reason. Every step is an activity event.

```ruby
config.impersonation.find_user = ->(tenant, id) { User.find(id) }
config.impersonation.sign_in = ->(controller, user) { controller.sign_in(:user, user) }
config.impersonation.sign_out = ->(controller) { controller.sign_out(:user) }
config.impersonation.entry_url = ->(tenant) { "https://#{tenant.subdomain}.example.com" } # only for another host
config.impersonation.return_url = ->(impersonation) { "https://example.com/backoffice" }
```

`bin/rails g lucid:backoffice:impersonation` adds the migration and the two routes served on the host of the tenant. Then include `Lucid::Backoffice::ImpersonationGuard` in your ApplicationController (blocks writes with 403, records one `page_view` per GET, attributes events to the operator, ends on expiry), `Lucid::Backoffice::ImpersonationMask` in ApplicationRecord (text hidden, dates reduced to the year, records read-only; a reveal of the operator releases its category), and render `lucid_backoffice_impersonation_banner` in the layout. `Lucid::Backoffice.impersonating?` tells your code, e.g. to block reflexes.

`Lucid::Backoffice::Impersonation.start(operator:, tenant:, user_id:, reason:)` needs the `:impersonate` permission and returns the impersonation and a one-time entry URL (valid 60 seconds). Starting another one ends the previous with `replaced`; `Impersonation.active_for(user:)&.end!(reason: "revoked")` ends it from the app.
