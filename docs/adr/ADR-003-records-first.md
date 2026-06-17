# ADR-003: Java records as default for immutable data types

**Date:** 2025-06  
**Status:** Accepted

## Decision
Use Java records as the default for all immutable types: DTOs, commands, responses,
event payloads, value objects, query params.
Fall back to Lombok `@Value`+`@Builder` only when a record is insufficient.

## Alternatives rejected
- **Lombok everywhere**: Records are a language feature — no annotation processing, no runtime dependency, exhaustive equals/hashCode/toString by default.
- **Plain classes**: Boilerplate; mutable by default.

## Consequences
- JPA entities remain classes (Hibernate requires mutable state).
- Records with compact constructors for validation — no separate validator class needed.
- Jackson deserializes records without extra config in Spring Boot 4.
