# Activity trail

An event is an immutable record of who did or tried what: name, outcome (`ok` or a failure type), actor, tenant, subjects (type and id), changed field names, an identifiers-only payload, reason, request id, IP and user agent. Never values of data: the payload accepts only integers, nil, booleans, arrays of integers and `[a-z_./]` tokens.

```ruby
Lucid::Backoffice::Activity.track("purchases.register") do |activity|
  purchase = Purchase.create!(attrs)
  activity.subject(purchase)
  purchase
end
```

`track` writes the event in the block's transaction (an error records nothing). A result answering `failure?` undoes the writes and records the failure type.

With `require "lucid/backoffice/integrations/lucid_case"` every Command records an event with nothing declared (lucid-case 0.4+); `require "lucid/backoffice/integrations/active_job"` carries the actor into jobs. Include `Lucid::Backoffice::Context` in your controllers to fill the actor and request. `bin/rails lucid:backoffice:purge` deletes events older than `activity_retention`.
