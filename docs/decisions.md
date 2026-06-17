# Decision Log

Running log of architectural and technical decisions. For formal ADRs see `docs/adr/`.
Reference with `@docs/decisions.md` in prompts when Claude re-raises settled questions.

| Date | Decision | Alternatives rejected | Reason |
|---|---|---|---|
| 2025-06 | WebMVC for business services; WebFlux for api-gateway only | WebFlux everywhere | Virtual threads give WebMVC near-reactive throughput; simpler testing; team familiarity. See ADR-001. |
| 2025-06 | Avro + Schema Registry for all Kafka messages | JSON, Protobuf | Schema enforcement, backward compat checking, Confluent tooling. See ADR-002. |
| 2025-06 | Records as default immutable type | Lombok @Value everywhere | Language feature; no annotation processing; cleaner compact constructors. See ADR-003. |
| 2025-06 | Choreography sagas via Kafka | Conductor orchestrator, 2PC | No single point of failure; works across PG + Mongo; no extra infra. See ADR-004. |
| 2025-06 | Soft-delete via deleted_at column | Hard DELETE, status column | Audit trail; event replay; no accidental data loss; consistent across all tables. |
| 2025-06 | Flyway for all schema changes; ddl-auto=validate | Liquibase, Hibernate auto-DDL | Flyway simpler API; validate catches drift early; industry standard for Spring. |
| 2025-06 | Redis cache-aside over Spring @Cacheable | @Cacheable | Explicit TTL control; explicit serialization; easier to test; no magic. |
| 2025-06 | Idempotency-Key header on all mutating endpoints | None (at-most-once) | Prevents duplicate charges/orders on network retry; required for Kafka consumer safety. |
| 2025-06 | Testcontainers for all integration tests | H2, EmbeddedMongo | Tests run against real engines; no behaviour divergence; catches index/type issues. |
| 2025-06 | Resilience4j for circuit breaking | Hystrix (EOL), manual | Active project; Spring Boot 4 native support; annotation-driven; no extra infra. |
