# Tenancy

`config.tenancy = :none` (default) is single-tenant. With `lucid-tenancy` (0.4+): `require "lucid/backoffice/adapters/lucid_tenancy"` and `config.tenancy = :lucid_tenancy`. The root lists tenants, each tenant has its data and a schema health section (`Lucid::Tenancy.health`), and reveals are per tenant. Write your own adapter by answering `tenants`, `find`, `identifier`, `label`, `schema_for`, `shared_schema`, `health`, `multi_tenant?`.

## Contexts

The panel always works in one context: the **shared** one (data outside any tenant, e.g. the shared schema; it is the only context without tenancy) or **one tenant**, entered from the card in the sidebar or the tenant list. The card, the tables, the activity and the reveals follow the context. The layout only uses the adapter (`multi_tenant?`, `tenants`, `find`, `identifier`, `label`, `schema_for`, `shared_schema`), never `lucid-tenancy` directly, and with `multi_tenant?` false the word tenant never appears. Rename the shared context with `config.terms = { shared: "Platform" }`.
