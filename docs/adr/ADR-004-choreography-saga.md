# ADR-004: Choreography-based sagas over orchestrated sagas

**Date:** 2025-06  
**Status:** Accepted

## Decision
Use choreography-based sagas via Kafka events for cross-service transactions.
No central saga orchestrator. No 2-phase commit.

## Alternatives rejected
- **Orchestrated saga (e.g. Conductor)**: Single point of failure; additional infrastructure; couples services to orchestrator.
- **2-phase commit / distributed transactions**: Unavailable across heterogeneous databases (PG + Mongo); performance impact; fragility.

## Consequences
- Each service publishes success or failure events after its local transaction.
- Compensating transactions triggered by failure events.
- Saga flows documented in `docs/sagas/<name>.md`.
- Harder to trace overall saga state — mitigated by structured logging with `correlationId`.
