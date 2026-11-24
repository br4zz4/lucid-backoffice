# Lucid Backoffice — context

Glossary of the panel's domain. No implementation detail.

## Terms

**Operator** — the person signed in to the panel. Comes from the app (`current_operator`); the gem never owns operators.

**Context** — the data space the operator is working in. There is always the **shared context**; each tenant is one more context. The operator is always inside exactly one context, chooses it in the sidebar and sees the tables, activity and reveals of that context only.
_Avoid_: area, scope, workspace.

**Shared context** — the context of data that belongs to no tenant (the shared schema, e.g. `public`). It is the default context and the only one in a panel without tenancy. Dashboard, the tenant list, plugin menus and the global activity live here.
_Avoid_: global area, public area.

**Tenant context** — the context of one tenant, entered by choosing it. Holds the tenant overview (schema health, tenant sections), its tables and its activity.

**Column category** — the privacy class of a column, from the classification YAML: `public`, a sensitive category (`contact`, `documents`, …), `unclassified`, or `secret`.

**Masked column** — a column whose category is neither `public` nor revealed for the operator in the current context. Its value never leaves the server in clear.

**Hidden column** — a column the panel never shows nor lets anyone filter by: `secret` category or listed in a Resource's `hide`.

**Reveal** — an operator unmasking, with a reason and for a limited time, every category they may reveal in one context. Recorded per category; ending it ends all of them.
_Avoid_: unmask, unlock.

**Visible column** — a column the operator can read right now: `public`, or masked but revealed. Only visible columns can be searched, filtered or sorted.

**Action** — the only way the panel writes to the app's data: declared in code, with a reason, a preview, a permission and an activity event.

**Record action** — an Action derived from a Resource declaration (`creatable`, `editable`, `destroyable`) instead of written by hand. Same guarantees as any Action.

**Locked field** — a form field over a masked column: shown as dots, disabled, never submitted. Revealing its category turns it into a normal input with the current value.
