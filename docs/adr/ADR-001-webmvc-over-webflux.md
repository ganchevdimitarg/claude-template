# ADR-001: WebMVC for business services, WebFlux for api-gateway only

**Date:** 2025-06  
**Status:** Accepted

## Decision
Use Spring WebMVC (servlet stack) for all business microservices.
Use Spring WebFlux only in `api-gateway` (Spring Cloud Gateway requires it).

## Alternatives rejected
- **WebFlux everywhere**: Steeper learning curve; Testcontainers + reactive testing is complex; most team members are experienced with servlet model; no I/O-bound bottlenecks that justify full reactive stack in business services.
- **Mixed per-service**: Inconsistency in error handling, test patterns, and filter chains.

## Consequences
- Virtual threads (Java 25) give WebMVC near-reactive throughput without reactive complexity.
- All team members can write and review code consistently.
- `OncePerRequestFilter` for MDC; `SecurityFilterChain` for auth — standard patterns.
