# Plugins and screens

```ruby
Lucid::Backoffice.register(:orgs) do |r|
  r.menu(label: "Organizations", path: "/backoffice/orgs", permission: :view_orgs)
  r.card(:orgs_total, label: "Organizations", value: ->(period) { Org.where(created_at: period.range).count })
  r.tenant_section(:orgs, partial: "orgs/section", permission: :view_tenant)
  r.permission(:view_orgs)
end
```

A screen of your own inherits `Lucid::Backoffice::ApplicationController` and gets the layout, authentication, authorization and activity context.
