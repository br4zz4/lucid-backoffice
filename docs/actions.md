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
