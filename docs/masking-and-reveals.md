# Masking and reveals

Masks: `nil` shows `—`, text over 40 characters `[texto, N caracteres]`, short text `•••••`, dates `••/••/••••`, numbers and booleans `•••`. Public columns and revealed categories show the real value.

`Lucid::Backoffice::Reveal.grant(operator:, tenant:, category:, reason:)` needs the `:reveal` permission and a reason of at least `reveal_reason_min` characters. It lasts `reveal_duration`, belongs to that operator, tenant and category, and `Reveal.revoke` ends it at once. Grant and revoke are recorded as activity events with the reason.

## The eye

A reveal is made with the eye in the top bar, next to Sign out: one click opens a modal, one reason (`reveal_reason_min`) reveals, for `reveal_duration`, every category the operator may reveal in the current context (`Reveal.grant_all`). The host app's `authorize` is asked per category and denied ones are skipped; if none is allowed, the answer is 403. While a reveal is active the eye shows when it ends, and clicking it ends all of them (`Reveal.revoke_all`). A reveal belongs to the context it was made in: entering another tenant starts masked again.

The routes are `POST /reveals` (optional `tenant_id`, no `category`) and `DELETE /reveals` (optional `tenant_id`). Each category still gets its own `Reveal` row and its own activity event, all with the same reason.

## What a reveal frees

A revealed category frees reading, searching, filtering and sorting by its columns, and editing them in Action forms. Without it the column is masked in lists and previews, absent from the filter menu, and its form field is locked. Ending the reveal makes stored search criteria on those columns ignored, with a warning.
