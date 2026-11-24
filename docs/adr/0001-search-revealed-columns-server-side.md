# Revealed columns are searchable, with the criteria kept server-side

Search, filters and sorting work on every **visible column**: `public` columns always, masked columns only while the operator has an active Reveal in the current context, hidden columns (`secret` or `hide`) never. Criteria on `public`, `id` and `*_id` columns may travel in the URL (`?filter[user_id]=42`); criteria on a revealed column are posted, kept in the encrypted session under an opaque token, and the list is reached by `?q=<token>`. When the Reveal ends, those criteria are ignored and the operator is told so.

This narrows a consequence of lunetamagica's ADR 0004 ("search limited to ids and public columns; searching masked columns would leak values by oracle"). The oracle only exists while the column is masked: once revealed, with a reason and a deadline, the operator already reads every value of that category in the context, so searching it leaks nothing new.

## Considered Options

- **Public columns only (ADR 0004 as written)**: rejected. Operators reveal a category precisely to find someone by email or name, and then cannot search for them.
- **Revealed criteria in the URL**: rejected. The URL reaches browser history, proxies and access logs, and the security rules forbid any column value in a URL.
- **Searching masked columns without a Reveal**: rejected. It is the oracle ADR 0004 warns about.

## Consequences

- The `browse` activity event records which columns were used as criteria, never their values.
- `Resource.search` accepts any non-hidden column; whether it applies is decided per request by the operator's Reveals.
