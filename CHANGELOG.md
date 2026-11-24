# Changelog

## 0.3.0

New layout: a sidebar with the current context, a top bar with the reveal eye and Sign out, a standard page header and an empty state. Works with and without tenancy.

- **Context:** the shared context (the default, and the only one without tenancy) and one context per tenant. The sidebar card shows where the operator is, with "Switch" / "Leave tenant" only when the adapter answers `multi_tenant?`. Tables, activity and reveals belong to the context. New screen `/tenants/:tenant_id/activity`.
- **Reveal eye:** one button in the top bar next to Sign out. One click opens a modal, one reason reveals every category the operator may reveal in the context (`Reveal.grant_all`); an active reveal shows "Revealed until HH:MM" and ends all of them with one click (`Reveal.revoke_all`). One `backoffice.reveal.grant`/`revoke` event per category.
- **Page header:** breadcrumb in the top bar, title, subtitle and Actions on the right. More than 3 Actions go into a menu; an unavailable Action is a disabled button with the reason under it. Fixes the Action button text that was invisible on the accent background.
- Empty tables show a message; the pager shows "1–50 of N"; the dashboard lists an "Enter →" button per tenant.
- New `configuration.terms[:shared]` renames the shared context.

### Breaking

- `POST /reveals` ignores `category` and reveals every category the operator may reveal. `DELETE /reveals/:id` is gone; use `DELETE /reveals` (ends all the operator's reveals in the context).
- The `ui/_reveal_toggle` partial and its CSS (`lb-reveal`, `lb-reason-form`) are gone, and so is the top `lb-nav`: apps that override `ui/*` or use `config.layout` should render `lucid/backoffice/shared/topbar` (sidebar, eye and Sign out) or keep their own layout.
- `ui/_actions` no longer renders its own section and heading; it is rendered by `ui/_page_header`.
- Custom tenancy adapters must answer `multi_tenant?` (the bundled ones do).

## 0.2.4

- The actions of a record are evaluated inside its tenant, so guards that query tenant tables (`unavailable`, `only_if`) work on the data screen.

## 0.2.3

- `Action.redirect_to { |value| url }`: where the operator goes after a successful run (used by impersonation to open the tenant host).

## 0.2.2

- `config.sign_out_method` (default `:get`): with `:delete` the layout renders a button instead of a link, which is what Devise's `sign_out_via :delete` needs.

## 0.2.1

- The Lucid::Case integration ignores events without a name (anonymous Commands) instead of failing the Command.

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
