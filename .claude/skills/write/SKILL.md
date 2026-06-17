---
name: write
description: Implement a feature end-to-end following project conventions. Triggers on /write.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

## Steps

1. Read relevant existing code first — service, repository, domain model, existing tests.
2. Plan: list every file to create or modify. If schema changes are needed, state the next Flyway version number.
3. Implement in this order: Flyway migration → domain model → repository → service → controller.
   Schema-first: migration runs first so `flyway:validate` passes from the start.
4. Use records for all immutable types (DTOs, commands, responses, events, value objects). Apply Lombok only when record is insufficient: @Getter+@Setter+@NoArgsConstructor on JPA entities; @RequiredArgsConstructor on @Service; @Slf4j for logging.
5. Use Java 25 features: records for data carriers, sealed+switch for unions, ScopedValue for request context, StructuredTaskScope for parallel calls.
6. Write unit tests (JUnit 5 + AssertJ, real domain objects, no Mockito on domain logic).
7. Write integration tests extending AbstractIntegrationTest (Testcontainers — never H2).
8. Add observability: MDC traceId/userId at entry point, structured log on key operations, MeterRegistry counter for significant actions.
9. Run: `./mvnw clean verify` (single-module repo; for a future monorepo add `-pl <module> -am`)
10. If verify fails:
    - Attempt to fix the root cause.
    - If the failure is a Flyway version conflict, migration checksum error, or unresolvable compilation error:
      revert partial changes with `git restore src/` before stopping.
    - Report exactly what blocked and what was reverted. Do not leave the repo in a broken state.
    - Do not suppress errors or skip tests to force a pass.
11. Re-run verify after every fix. Do not stop until fully green.

## Lombok rules
- Records for all DTOs, commands, responses, event payloads, value objects — default choice for immutable data
- @Builder on commands/responses only when record is insufficient (custom Jackson deserializer, framework requires no-arg constructor)
- @RequiredArgsConstructor on @Service/@Component
- @Slf4j for all logging
- @Value for immutable DTOs only when record cannot be used
- @Getter + @Setter + @NoArgsConstructor on JPA entities
- Never @Data on JPA entities
- Never @ToString/@EqualsAndHashCode on JPA entities with associations

## Flyway rules
- New table → V<n+1>__create_<table>.sql
- Every CREATE TABLE migration must include audit columns: `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `deleted_at TIMESTAMPTZ NULL`
- New column → V<n+1>__add_<column>_to_<table>.sql
- New index → separate migration from table creation
- Never edit existing migration files

## Redis rules
- Jackson JSON serialization only
- Key: `<service>:<entity>:<id>`
- Always set TTL

## Avro / Schema Registry rules
- When adding a new Kafka event: first create or update the `.avsc` file in `common-events/src/main/avro/<domain>/`
- Every new field MUST have a `"default"` value — never add a field without one
- Never remove, rename, or change the type of an existing field — add a new field instead
- Run schema compatibility check: `./mvnw schema-registry:register -pl common-events`
- Generate Java classes from schema: `./mvnw generate-sources -pl common-events` before referencing in service code
- Register schema BEFORE writing the producer code

## Kafka rules
- Topic: `<domain>.<entity>.<event>`
- Always set traceId and correlationId as message headers
- Check correlationId in Redis for idempotency before processing

## Validation rules
- Bean Validation constraints on record components (`@NotNull`, `@Size`, `@Pattern`, `@NotEmpty`)
- `@Valid` on all `@RequestBody` and `@PathVariable` controller params — never skip
- Cross-field / business rules in record compact constructor throwing `ValidationException`
- Never re-validate in service layer what is already declared on the record

## Pagination rules
- Controller accepts `@PageableDefault(size = 20, sort = "createdAt", direction = DESC) Pageable pageable`
- Service returns `Page<ResponseRecord>` — never `Page<Entity>`
- Wrap with `PageResponse.of(page)` before returning from controller
- Enforce max page size `@Max(100)` on `size` request param

## Security rules
- Declare explicit SecurityFilterChain bean — no auto-config defaults
- @PreAuthorize on service layer methods