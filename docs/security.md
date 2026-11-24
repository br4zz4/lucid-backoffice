# Security

Denies by default; fails closed (an activity event that cannot be written stops the read); no SQL write on the app's tables from any GET; table and column names come only from the catalog; no column value in logs, errors, URLs or payloads; secret columns never shown; CSRF on the only non-GET routes (`POST /reveals`, `DELETE /reveals` and `POST /actions/:action_key`). It never edits data in v0.1.
