# Masking and reveals

Masks: `nil` shows `—`, text over 40 characters `[texto, N caracteres]`, short text `•••••`, dates `••/••/••••`, numbers and booleans `•••`. Public columns and revealed categories show the real value.

`Lucid::Backoffice::Reveal.grant(operator:, tenant:, category:, reason:)` needs the `:reveal` permission and a reason of at least `reveal_reason_min` characters. It lasts `reveal_duration`, belongs to that operator, tenant and category, and `Reveal.revoke` ends it at once. Grant and revoke are recorded as activity events with the reason.
