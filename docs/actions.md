# Actions

The only way the back office writes. Everything else is read-only.

```ruby
class Actions::ChangeUserRole < Lucid::Backoffice::Action
  on :users
  field :role, :select, choices: -> { %w[teacher coordinator] }
  unavailable "School would have no owner", if: -> { record.last_owner? }
  perform { record.update!(role: role) }
end
```

`bin/rails g lucid:backoffice:action ChangeUserRole` creates the file in `app/backoffice/actions`, which is loaded at boot and on reload.

- **Targets:** `on :users` (a record of that table), `on :tenant`, `on :global`.
- **Fields:** `:string :text :integer :boolean :date :select :record`, or `partial:` for your own input. A field named like an attribute of the record starts with its current value (`initial_values`); a required field must still be submitted.
- **Preview:** by default each field named like an attribute shows before and after, masked by the category of the column. Write `preview { |p| p.change(record, :role, to: role); p.list("Versions", pending) }` for anything else. The state read for the preview is compared at execution: if it changed, nothing runs.
- **Availability:** `only_if { }` hides the action, `unavailable "why", if: -> { }` shows it disabled with the reason.
- **Danger:** `danger :high` asks the operator to type the tenant identifier (or the record id).
- **Execution:** a mandatory reason, the permission of the action (`:run_action` by default), a transaction (`transaction false` to opt out, e.g. HTTP) and one `backoffice.action.<key>` event with the reason.
- **With a Command:** `perform with: Users::ChangeRole` passes the fields as attributes (plus `record` and `tenant` when the Command declares them). A failure shows `result[:errors].first`, or `lucid_backoffice.actions.<key>.failures.<type>`, or the humanized type. The Command's own event and the action event both stay.
- **Reason:** `reason` inside `perform` is the reason the operator typed (the same one recorded in the event).
- **Redirect:** `redirect_to { |value| url }` sends the operator somewhere after a successful run (for example the one-time URL of an impersonation) instead of back to the screen. The URL comes from the app, never from a parameter.
- **Editable:** `editable :name, :city` on a Resource, optionally `with: Organization::Update`.

Bulk actions are not supported yet.

## Collection actions, locked fields, submit options and secrets

- **Collection:** `on :users, collection: true` is an Action on the table as a whole (no record), offered in the header of its list. `landing :record` / `landing :list` chooses where the operator goes after it succeeds.
- **Locked fields:** a field named like a column of the record's table whose category is not `public` (or that is hidden) is shown as dots, disabled and never submitted, with or without a reveal; the value the Action receives is read on the server. The operator opens one field at a time:
  - **Unlock** (a masked column): reads the current value with `POST /actions/:action_key/fields/:field/unlock` (`no-store`), needs `:reveal` for the column's category, and records a `backoffice.field.unlock` event (table, column, record id and Action; no value, no reason). The field becomes a normal input and goes back to dots when the operator leaves it, with an eye to peek; the value is still submitted.
  - **Set new value** (a `secret` or hidden column): the current value is never read; the field opens empty. A blank value keeps the current one.
  - The form submits `unlocked[]` with the opened names. The server uses a submitted value only for a listed field the operator may reveal; otherwise it uses the current value. Or classify the column as `public` to skip all this.
- **Submit options:** `submit :email, label: "Send by email", if: -> { email_available? }` replaces "Execute" with one button per available option. The chosen key is `submitted` in the Action and the `submit` attribute of a Command that declares it. An option that is not offered is refused.
- **Email available:** `email_available?` asks `config.email_available`, or reads the ActionMailer settings (`perform_deliveries`; `:smtp` needs an address other than localhost; any other registered delivery method counts). The gem never knows the provider.
- **One-time secret:** `secret { |value| string }` shows the value once after a successful run (200, `Cache-Control: no-store`, a read-only field with a copy button, never a link). It never goes into flash, session, the activity event or logs.
