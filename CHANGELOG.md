# Changelog

## 0.5.2

- **Fix:** the top bar no longer has a `backdrop-filter`. The sidebar is `position: fixed` inside the top bar, and any filter on an ancestor turns that into the top bar's own box, which squeezed the sidebar into it and let the breadcrumb show through. The top bar is a solid black again; the sidebar keeps its glass.

## 0.5.1

Fixes found reviewing 0.5.0.

- **Fix:** an unlocked field no longer gets lost between the preview and the execution, and no field value (an unlocked masked value, a new secret) nor the CSRF token reaches the URL: the preview is `POST /actions/:action_key/preview`, and a field the operator unlocked comes back open, hidden and with its value, ready to execute.
- **Fix:** an Action form sent from a panel without a tenant answered 404, because the empty `tenant_id` hidden field was read as a tenant; a blank `tenant_id` now means no tenant.
- **Fix:** the countdown no longer reads a page as edited just because a `<select>` has no explicit option, so the list pages mask again by themselves at zero; the hide-value button works on Safari and Firefox for macOS; the automatic `DELETE /reveals` is sent once (with a fallback for browsers without `requestSubmit`); the unlock error is announced and the show/hide toggle exposes `aria-pressed`.

## 0.5.0

A finished look for the panel, a countdown on the reveal, and one-field-at-a-time unlocking in Action forms (ADR 0002).

- **Look:** forms, sections and tables as cards with a violet glow behind a black panel; focus rings, a chevron on selects, glass on the sidebar and top bar. The sidebar's current item is plain text on a soft background (no border, no bar), table names are truncated with the full name as `title`, and the "Data" heading is sans, not mono. Search has a magnifier and Enter submits; the "+ Filter" popover has visible Column and Value labels and an "Apply filter" button; filter chips look like tags.
- **Countdown:** the eye shows `Revealed · mm:ss` (the time it ends is its `title`), from the seconds the server reports (`data-lb-remaining`), amber in the last minute. At zero a clean page sends the eye's own `DELETE /reveals` and comes back masked, without a notice; a page with unsaved edits keeps them, shows `Expired` in red and blurs what was shown as revealed until the operator masks again. Without JavaScript it still reads `Revealed until HH:MM`.
- **Revealed marks:** the server marks every value it shows revealed with `data-lb-revealed` (table cells, record detail, Action previews, filter chips). The Action preview no longer masks revealed values by default.
- **Unlock:** a field over a column that is not public starts locked in Action forms, with or without a reveal. "Unlock" (a masked column) reads the current value through `POST /actions/:action_key/fields/:field/unlock` (`no-store`), needs the `:reveal` permission of the category and records `backoffice.field.unlock` (table, column, record, action; no value, no reason). A `secret` or hidden column only offers "Set new value": the current value is never read. After leaving the field the value is hidden again, with an eye to peek.
- **Actions record what they changed:** the event of a transactional Action over a record now carries the record as subject and the names (never the values) of the attributes it changed.

### Breaking

- A Reveal no longer unlocks Action form fields. A submitted value for a locked field is used only when the field is listed in `unlocked[]` and the operator may reveal its category (a hidden column also needs a non-blank value); otherwise the current value is used.
- `Action#initial_values` and `Action#locked_names` no longer take `revealed:`; `Action#with_locked_current` takes `unlocked:` and `operator:`; `Action::Runner.call` takes `unlocked:` instead of `revealed:`.
- `Records::Cell` and `Action::Preview::Change` gain a `revealed` attribute (default `false`).
- `DELETE /reveals` with nothing to end no longer shows the "Reveal ended" notice.

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
