# Tenancy

`config.tenancy = :none` (default) is single-tenant. With `lucid-tenancy` (0.4+): `require "lucid/backoffice/adapters/lucid_tenancy"` and `config.tenancy = :lucid_tenancy`. The root lists tenants, each tenant has its data and a schema health section (`Lucid::Tenancy.health`), and reveals are per tenant. Write your own adapter by answering `tenants`, `find`, `identifier`, `label`, `schema_for`, `shared_schema`, `health`, `multi_tenant?`.
