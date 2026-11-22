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

`search` only accepts public columns (searching a masked column would leak it by trial and error); `label` and `column ... render:` take `from:` so the value is masked by the category of its source column, and without `from:` it counts as `unclassified`.
