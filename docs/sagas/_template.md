## Saga: <Name>

### Trigger
<which event or HTTP call starts this saga>

### Steps & events
1. Service A: <local transaction> → publishes <EventA>
2. Service B: consumes <EventA>, <local transaction> → publishes <EventB>
3. ...

### Compensation (on failure at step N)
- Step N failure → <compensating event or action>
- ...

### Invariants
- <business rule that must hold across all steps>

### Notes
- <gotchas, ordering constraints, idempotency keys used>
