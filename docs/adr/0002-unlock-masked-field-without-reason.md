# A masked field is unlocked for editing without a reason, leaving an event

In Action forms every field over a non-`public` column starts locked, even while a Reveal is active. The operator opens one field at a time. Over a masked column the unlock reads the current value through `POST`, with `Cache-Control: no-store`, and requires the `:reveal` permission for that category in the context; it records a `backoffice.field.unlock` event with the table, column, record id and Action key, never the value, and asks for no reason. Over a hidden column (`secret` or `hide`) nothing is read: the operator only writes a new value. The Action that saves the change still needs its reason, preview and permission, and its event records the names of the changed fields, never values.

A Reveal needs a reason because it opens a whole category across the context for a period. An unlock opens one value of one record, for the purpose of editing it, and the edit itself is justified by the Action's reason. Asking for a second reason before the operator has typed the first adds friction without adding information to the trail.

## Considered Options

- **Unlock only through the Reveal (0.4.0)**: rejected. Correcting one field forced revealing every category for the whole context, which exposes far more than the edit needs.
- **Unlock with its own reason**: rejected. Two reasons for one edit, and the second one rarely says more than the Action's.
- **Unlock without an event**: rejected. Reading a masked value would leave no trace when the operator gives up without saving.
- **Write-only for masked columns too**: rejected. Masked categories may be read by whoever may reveal them; correcting a value one cannot see leads to blind overwrites.
- **Values (before and after) in the activity event**: rejected. The trail would become one more copy of personal data to protect, retain and purge.

## Consequences

- The server accepts a submitted value for a non-`public` field only when the field comes marked as unlocked and the operator holds the permission it required; otherwise the current value is used, as before.
- The Reveal deadline never touches forms: a form keeps working after the Reveal ends.
