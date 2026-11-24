# Resources

A table works with no declaration. A resource only adjusts it:

```ruby
class Purchases < Lucid::Backoffice::Resource
  table :purchases
  group :billing
  columns :id, :email, :status
  hide :internal_note
  column :status, :badge
  search :id
  filter :status
  association :items, table: :purchase_items, foreign_key: :purchase_id
  label(from: :email) { |row| row["email"] }
end
```

`search` names the columns the text search covers (default: every text column). A hidden column (`hide`, `secret_columns`) can never be searched; a masked one is searched only while the operator has revealed its category. `filter` suggests the filters of the "+ Filter" menu. `association :items, table: :purchase_items, foreign_key: :purchase_id` adds a table to "Related". Foreign keys of the database and `x_id` => `xs` are found by themselves. `label` and `column ... render:` take `from:` so the value is masked by the category of its source column, and without `from:` it counts as `unclassified`.

## Creating, editing and deleting

Nothing is writable unless declared. Each declaration generates an Action and takes an optional block to configure it:

```ruby
class Users < Lucid::Backoffice::Resource
  table :users
  creatable :name, :email, :role, with: User::Invite do
    label "New user"
    field :role, :select, choices: -> { User.role.values }, default: "owner"
    submit :email, label: "Create and send by email", if: -> { email_available? }
    submit :link, label: "Create and copy link"
    secret { |result| result[:set_password_url] }
  end
  editable :name, :email, :role
  destroyable
end
```

| declaration | key | permission | default write |
|---|---|---|---|
| `creatable *cols, with:` | `create_<table>` | `:create_record` | `Model.create!` |
| `editable *cols, with:` | `edit_<table>` | `:update_record` | `record.update!` |
| `destroyable with:` | `destroy_<table>` (`danger :high`) | `:destroy_record` | `record.destroy` |

Validation errors become a readable failure and nothing is written. `creatable` and `destroyable` need an ActiveRecord model for the table and `creatable` refuses hidden columns, both at boot.
