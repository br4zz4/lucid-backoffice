# Changelog

## 0.1.0

Initial release.

- Read-only panel over the tables of the app (and of each tenant), with every column masked by default.
- Classification in a versioned YAML; convention for `id`, `*_id`, `*_type`, `created_at`, `updated_at`.
- Reveals by category, per operator and tenant, with a mandatory reason and a deadline.
- Activity trail: `Activity.track`, optional `lucid-case` and `active_job` integrations, purge task, activity screen.
- Authentication, roles and permissions through configuration (`authorize` denies by default).
- Tenancy adapters: single-tenant and `lucid-tenancy`.
- Resources DSL, dashboard cards, plugin registry, screens of the app inside the layout, generator and test helpers.
