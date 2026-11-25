# Changelog

## 0.4.1

- **Fix:** the Action form carries the `authenticity_token`. It is a GET form whose execute button posts (`formmethod: :post`), and Rails adds no token to GET forms, so every Action run answered 422 once forgery protection was on.

## 0.4.0

Manage data in the panel: search, filter and sort by the columns the operator can read, follow foreign keys, and create, edit or delete records the app declared, always as an Action (reason, preview, permission, event).

- **Query:** a text search, equality filters and sorting over the visible columns: public ones always, masked ones only while their category is revealed. Criteria on masked columns go through `POST /data/:table/query` and are kept in the session (`?q=<token>`), never in the URL or the logs; `backoffice.browse` records column names only (ADR 0001).
- **Relations:** foreign-key values link to the record; "Related" lists the tables that point at it, with counts.
- **Record actions:** `creatable`, `editable` and `destroyable` on a Resource generate the Actions (`create_<table>`, `edit_<table>`, `destroy_<table>`), with permissions `:create_record`, `:update_record`, `:destroy_record`. They take a block to configure the generated Action (`label`, `field`, `submit`, `secret`, `preview`, ...). Collection Actions (`on :users, collection: true`) appear in the header of the list.
- **Locked fields:** an Action field over a masked column is shown as dots, disabled and never submitted; the server reads the current value. Closes a leak of `initial_values`.
- **Submit options:** `submit :key, label:, if:` gives several execute buttons; `email_available?` (from the ActionMailer settings, or `config.email_available`) lets an app hide the email one.
- **One-time secret:** `secret { |value| string }` shows a value once, to copy, after the Action runs (no redirect, `no-store`, never in flash, session, activity or logs).

### Breaking

- `editable` Actions now need the permission `:update_record` (was `:run_action`).
- `Resource.search` accepts masked columns (they are searched only while revealed); it refuses only hidden ones.
- `Records.list` takes `query:`; `Action#initial_values` takes `revealed:` and returns `Action::Field::LOCKED` for masked columns; `Runner.call` takes `revealed:` and `submit:`.
- An Action field named like a non-public column of its record is locked unless the category is revealed: classify the column as `public` if the operator should always edit it.

## 0.3.1

- **Fix:** `GET /assets/lucid_backoffice.js` answered 422 in apps with `protect_from_forgery` (Rails blocks cross-origin JavaScript GETs), so no JS ran. `AssetsController` skips forgery protection (it only serves public static files).
- The reveal eye works without JavaScript (`<details>` panel, no disabled submit).
- The shared context is called "Home". Breadcrumb in muted colors on one line (last item only on mobile); sidebar items look like buttons.

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
