# Changelog

## 0.2.0

Corrective actions and impersonation.

- `Lucid::Backoffice::Action` DSL: `on`, `field`, `only_if`, `unavailable`, `preview`, `perform` (a block or `with:` a Lucid::Case Command), `result`, `danger`, `transaction`. The preview, the state check, the mandatory reason, the permission and the `backoffice.action.<key>` event are derived.
- `editable` on a Resource generates an "Edit" action over only the listed fields.
- Impersonation: read-only, masked, time-boxed, one-time token, page views recorded, banner, `ImpersonationGuard` and `ImpersonationMask` for the app.
- Generators `lucid:backoffice:action` and `lucid:backoffice:impersonation`.
- `Activity.track(undo_on_failure:)`.

## Unreleased

- New default look inspired by brazza.tech: black surfaces, lime accent, hairline borders, pill buttons, mono labels. System font stacks, no external requests.
- Design tokens as CSS custom properties (`--lb-bg`, `--lb-accent`, ...), served by `assets/theme.css` (no inline styles, CSP friendly) and set with `config.theme` and `config.brand_color`.
- `config.stylesheet` replaces the gem's CSS entirely; `config.extra_stylesheets` adds to it. Values are validated at boot (`ConfigurationConflict`).
- `lucid/backoffice/shared/_head` partial so a custom `config.layout` gets the same assets.
- Assets are served with ETag and `X-Content-Type-Options: nosniff`.

## 0.1.0

Initial release.

- Read-only panel over the tables of the app (and of each tenant), with every column masked by default.
- Classification in a versioned YAML; convention for `id`, `*_id`, `*_type`, `created_at`, `updated_at`.
- Reveals by category, per operator and tenant, with a mandatory reason and a deadline.
- Activity trail: `Activity.track`, optional `lucid-case` and `active_job` integrations, purge task, activity screen.
- Authentication, roles and permissions through configuration (`authorize` denies by default).
- Tenancy adapters: single-tenant and `lucid-tenancy`.
- Resources DSL, dashboard cards, plugin registry, screens of the app inside the layout, generator and test helpers.
