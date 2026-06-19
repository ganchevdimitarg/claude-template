# CLAUDE.md

> **Repo maturity — read first.** This is a **single-module Spring Boot template**
> (`com.ganchevdimitarg.claudetemplate`), not yet a multi-service platform. The
> conventions below describe the *target* architecture. Sections on Kafka, MongoDB,
> Avro/Schema Registry, api-gateway, choreography sagas, and cross-service resilience
> are **aspirational** — apply them only once the corresponding module actually exists.
> Until then, treat `<service-name>` as a placeholder and prefer the single-module
> guidance in `docs/context/project-layout.md`. Do not scaffold infrastructure the repo
> has no code for.

---

## Context loading (progressive disclosure)

Core conventions in this file are always in context. **Detailed pattern files load on
demand** — read the file when the task actually touches that area, not before. This keeps
every session lean and avoids paying the token cost of infrastructure the repo has no code
for yet. The `@import` lines below pull in only the cross-cutting patterns that apply to
*any* code in this repo; everything situational is in the table.

| When you work on… | Read on demand |
|---|---|
| Outbound HTTP / circuit breakers | `docs/context/resilience.md` |
| Mutating cross-service endpoints | `docs/context/idempotency.md` |
| Redis / caching | `docs/context/caching.md` |
| Kafka producers / consumers | `.claude/context/kafka-setup.md` |
| Avro schemas / Schema Registry | `docs/context/avro-patterns.md` |
| MongoDB documents / queries | `docs/context/mongodb-patterns.md` |
| Dockerfiles | `docs/context/docker-patterns.md` |

**Always loaded** (imported inline below): Java 25 platform, Lombok/records, security,
pagination, exceptions, validation, database, Testcontainers, project layout.

## Stack
- Java 25 · virtual threads default · ScopedValue over ThreadLocal · SequencedCollection APIs · records preferred over classes for data carriers
- Spring Boot 4 · WebMVC for business services · WebFlux for api-gateway · no XML config · problem+json errors (RFC 9457)
- PostgreSQL · Flyway migrations · JSONB only for schemaless data · typed columns preferred
- MongoDB · <service-name> only · aggregation pipeline over app-side joins
- Redis · Lettuce · JSON serialization (Jackson) · keyspace: `<service>:<entity>:<id>` · TTL always set
- Kafka · Schema Registry (Avro) · topic: `<domain>.<entity>.<event>` · consumer group: `<service>-group` · DLT: `<topic>.DLT`
- Docker · multi-stage builds · non-root user · HEALTHCHECK mandatory · explicit artifact name in COPY
- Lombok · annotation rules in conventions below
- Flyway · all schema changes via versioned migrations · never alter schema in code

---

## Architecture
- Each service owns its schema — no cross-DB joins, no shared datasources
- Sync: REST/WebMVC for reads in business services; WebFlux in api-gateway; async Kafka events for cross-service writes
- No shared libraries except `common-events` (Avro schemas) and `common-test` (Testcontainers base)
- Resilience4j circuit breaker + bulkhead on every outbound HTTP call
- API Gateway owns auth/rate-limit; downstream services trust `X-User-Id` / `X-User-Roles` headers
- API versioning: URL prefix `/api/v{n}/` — bump only on breaking changes; maintain n-1

---

## Java 25 & Spring Boot 4 Conventions

### New platform features — use these
- `ScopedValue` for request-scoped context (tracing IDs, user context) — never `ThreadLocal` on virtual threads
- `StructuredTaskScope` for parallel fan-out with automatic cancellation on failure
- `SequencedCollection` / `SequencedMap` where ordered access matters
- Sealed interfaces + exhaustive `switch` pattern matching for discriminated unions — no `instanceof` chains
- Records **preferred** for: DTOs, commands, query results, API request/response, event payloads, value objects — anything immutable with no JPA/persistence concern (see Lombok section below for canonical examples)
- Use `String.format()` or text blocks for multiline strings — no string concatenation in hot paths (String Templates, JEP 430, was withdrawn from Java 25)

@docs/context/java25-patterns.md

### Lombok
- `@Value` + `@Builder` on immutable DTOs, commands, events — only when record is not suitable (e.g. needs Jackson custom deserializer or inheritance)
- `@Builder` on domain entities (never `@Data` on entities)
- `@Getter` + `@Setter` + `@NoArgsConstructor` on JPA entities — nothing more
- `@RequiredArgsConstructor` on `@Service` / `@Component` — never `@Autowired`
- `@Slf4j` for all logging — never declare `Logger` manually
- Never `@EqualsAndHashCode` on JPA entities — implement manually or use `@NaturalId`
- Never `@ToString` on JPA entities with lazy associations — causes N+1 on log statements
- Never `@Data` on JPA entities or domain objects with business logic

@docs/context/lombok-records-patterns.md

### General
- `@Transactional` on service layer only — never on controllers or repository interfaces
- Repositories return `Optional<T>` — never null; service unwraps via `orElseThrow()`
- Never `Optional.get()` without guard — always `orElseThrow(() -> new NotFoundException(...))`
- Domain exceptions extend `BusinessException(HttpStatus, String code, String message)`
- No raw `500` responses — all errors via `@ControllerAdvice` producing `application/problem+json`

### Spring Security
- Stateless JWT validation at gateway; downstream services read `X-User-Id` / `X-User-Roles` headers
- Each service declares a `SecurityFilterChain` bean — never rely on Spring Boot auto-config defaults
- Method security (`@PreAuthorize`) on service layer, not controller

@docs/context/security.md

### Jackson
- Global config in `JacksonConfig` `@Configuration` bean — never per-controller `ObjectMapper`
- Property naming: `camelCase` for REST (default); never mix strategies across services
- Null serialization: `NON_NULL` globally — no null fields in API responses
- Dates: ISO-8601 strings (`JsonFormat.Shape.STRING`) — never epoch longs in DTOs
- Unknown properties: `FAIL_ON_UNKNOWN_PROPERTIES = false` on deserialization (tolerant consumer)

### Pagination
- Use `Page<T>` from Spring Data; wrap in a `PageResponse<T>` record for API responses
- Default page size: 20; maximum: 100 — enforce with `@Max(100)` on `size` param
- Controller accepts `Pageable` via `@PageableDefault(size = 20, sort = "createdAt", direction = DESC)`
- Never expose raw `Page<Entity>` — always map to `Page<ResponseRecord>` before wrapping

@docs/context/pagination-patterns.md

### Exception hierarchy
`BusinessException(HttpStatus, String code, String message)` is the base. Subclasses: `NotFoundException` (404), `ConflictException` (409), `ValidationException` (400).
`@ControllerAdvice` maps all → problem+json. Never catch and rethrow as `RuntimeException`.
@docs/context/exceptions.md

### Input validation
- Bean Validation constraints (`@NotNull`, `@Size`, `@Pattern`) on record components
- `@Valid` on controller method parameters — validated before reaching service
- Cross-field / business-rule validation in compact constructor of the record, throwing `ValidationException`
- Never validate in service layer what can be expressed as a Bean Validation constraint

@docs/context/validation-patterns.md

---

## Resilience4j & SLO defaults

Every outbound HTTP call must be wrapped with `@CircuitBreaker` + `@Bulkhead` + `@TimeLimiter`.
Default thresholds (override per-service in `application.yml`): failure rate 50%, slow call 2s, wait open 30s, half-open 5 calls, bulkhead 10 concurrent, timeout 5s.
Fallback method must have same signature as original + `Throwable` param.
→ Detail on demand: `docs/context/resilience.md` (load only when adding outbound HTTP calls).

---

## Idempotency

All mutating REST endpoints (POST, PUT, PATCH) that cross a service boundary or modify
persistent state must support idempotency via `Idempotency-Key` header.

- Client sends `Idempotency-Key: <uuid>` on every mutating request
- Check Redis key `idempotency:<service>:<idempotency-key>` before processing; return cached response on hit
- On miss: process, store response with 24h TTL, return
- Key is never per-user — scoped to service only
- Never implement a POST/PUT/PATCH that mutates without idempotency support
→ Detail on demand: `docs/context/idempotency.md` (load when adding a mutating endpoint).

---

## Observability
- All services include `spring-boot-starter-actuator` + `micrometer-tracing-bridge-otel`
- Trace context propagated via W3C `traceparent` header on all HTTP and Kafka messages
- MDC keys: `traceId`, `spanId`, `userId`, `serviceId` — set at request entry point, cleared on exit
- Structured JSON logging (Logback + logstash-logback-encoder) — no plain-text log format in prod
- Kafka consumer sets MDC from message headers before processing, clears after

`MdcRequestFilter extends OncePerRequestFilter`: `MDC.put("traceId", req.getHeader("traceparent"))` + `MDC.put("userId", req.getHeader("X-User-Id"))` in try; `MDC.clear()` in finally.

- Custom metrics via `MeterRegistry` — name pattern: `<service>.<entity>.<action>` e.g. `order.payment.retried`
- Health indicators: DB, Redis, Kafka — exposed at `/actuator/health` (details for internal only)

---

## Distributed transactions — choreography saga

Never use 2-phase commit or synchronous cross-service writes.
Use choreography-based sagas via Kafka events:
- Each service publishes success or failure event after its local transaction
- Compensating transactions triggered by failure events — no central orchestrator
- Saga state reconstructed by replaying events — never stored in a shared table
- Document flows in `docs/sagas/<name>.md` with event sequence and compensations

---

## Feature flags

Gate new behaviour behind feature flags before full rollout:
- Simple on/off: `@ConditionalOnProperty(name = "features.new-pricing", havingValue = "true")`
- Runtime toggles: inject `FeatureFlagService` backed by Unleash or a Redis key
- Flags removed within one sprint of confirmed full rollout — never left permanently
- Flag names: `features.<service>.<feature>` e.g. `features.<service-name>.retry-v2`
- Never gate with a hardcoded `if (ENV == "prod")` — use the flag service

---

## Local development

Infrastructure via Docker Compose at repo root:
```bash
docker compose up -d          # starts PG, Mongo, Redis, Kafka, Schema Registry
./mvnw spring-boot:run -pl <service-name>   # run a single service
```

Port conventions (declared in root `docker-compose.yml`):
| Service | Port |
|---|---|
| PostgreSQL | 5432 |
| MongoDB | 27017 |
| Redis | 6379 |
| Kafka | 9092 |
| Schema Registry | 8081 |
| api-gateway | 8080 |
| <service-name> | 8081 (internal) |

Never: run all microservices simultaneously without Docker Compose for infra — use the compose file.

---

## Naming conventions

| Concept | Pattern | Example |
|---|---|---|
| Package | `com.example.<service>.<layer>` | `com.example.order.service` |
| Domain event | `<Entity><PastTense>Event` | `OrderPlacedEvent` |
| Command | `<Verb><Entity>Command` | `CreateOrderCommand` |
| Query | `<Entity>Query` | `OrderByCustomerQuery` |
| Service | `<Entity>Service` | `OrderService` |
| Repository | `<Entity>Repository` | `OrderRepository` |
| Controller | `<Entity>Controller` | `OrderController` |
| DTO / response | `<Entity>Response` | `OrderResponse` |
| Exception | `<Reason>Exception` | `OrderNotFoundException` |
| Kafka topic constant | `<DOMAIN>_<ENTITY>_<EVENT>` | `ORDER_PAYMENT_COMPLETED` |
| Config class | `<Subject>Config` | `JacksonConfig`, `SecurityConfig` |

---

## Caching strategy

Use Redis cache-aside pattern. Do NOT use Spring `@Cacheable` — it hides TTL and
serialization decisions and makes testing harder.

Cache:
- Read-heavy, rarely mutated data (product catalogue, config, user profile)
- Expensive computed results with a clear invalidation trigger
- Idempotency keys and correlation IDs (always)

Do NOT cache:
- Data that must be strongly consistent (account balances, inventory counts)
- Data the service owns and can read directly from its own DB with acceptable latency
- Anything with unclear invalidation logic

Invalidation strategies (pick one per use case):
- **TTL expiry**: for eventually-consistent reads — set TTL, let it expire
- **Write-through**: on every write to DB, also update/delete the cache key
- **Event-driven**: on Kafka event (e.g. `ProductUpdated`), delete the cache key

→ Detail on demand: `docs/context/caching.md` (load when introducing Redis caching).

---

## Flyway

All schema changes are versioned Flyway migrations. Never use `spring.jpa.hibernate.ddl-auto` other than `validate`.

### File naming
```
src/main/resources/db/migration/
  V1__create_orders_table.sql
  V2__add_status_index.sql
  V3__create_payments_table.sql

src/test/resources/db/migration/
  R__test_seed_orders.sql        ← repeatable; test seed data only
```

Rules:
- `V<n>__<snake_case_description>.sql` — two underscores, monotonically increasing
- `R__<description>.sql` for seed/reference data only (re-runs when checksum changes)
- Never edit a committed migration — always create a new version
- Each migration is one logical change; index = separate migration from table creation
- Always `IF NOT EXISTS` / `IF EXISTS` guards on DDL

@docs/context/database-patterns.md

---

## Redis

- Serialization: Jackson JSON (`GenericJackson2JsonRedisSerializer`) — never Java serialization
- Key pattern: `<service>:<entity>:<id>` e.g. `<service-name>:order:uuid`
- TTL: always set — no immortal keys; default 24h unless business rule differs
- Cache-aside pattern: read cache → on miss read DB → write cache with TTL
- Distributed lock: Redisson `RLock` for idempotency guards — never `SETNX` manually

→ Detail on demand: `docs/context/caching.md` (cache-aside / write-through / event-driven examples).

---

## Kafka

- Topic naming: `<domain>.<entity>.<event>` e.g. `order.payment.completed`
- Consumer group: `<service>-group` e.g. `<service-name>-group`
- Dead-letter topic: `<original-topic>.DLT` — configure via `@RetryableTopic`
- Retry: 3 attempts with exponential backoff before DLT; log and alert on DLT arrival
- All messages carry `traceId` and `correlationId` as headers
- Use `@KafkaListener` with explicit `groupId`; never rely on default group ID
- Idempotency: check `correlationId` in Redis before processing to prevent duplicate handling

→ Detail on demand: `.claude/context/kafka-setup.md` (producer/consumer config + patterns).

### Avro / Schema Registry
- All event schemas live in `common-events/src/main/avro/<domain>/` as `.avsc` files
- Schema subject: `<topic>-value` e.g. `order.payment.completed-value`
- Compatibility mode: **BACKWARD** — consumers on the old schema can read new messages
- Rules for safe evolution:
  - New field: always add a `"default"` value — never a field without one
  - Never remove, rename, or change the type of an existing field — add a new one
  - Never change a field from optional to required
- Register schema before producing; CI runs `mvn schema-registry:register` on `common-events` build

→ Detail on demand: `docs/context/avro-patterns.md` (schema layout, evolution, commands).

---

## MongoDB conventions (<service-name>)
- Declare indexes via `@CompoundIndex` on the document class or via Mongock migration scripts — never rely on auto-index creation in prod
- Always index every field used in `find()` / `$match` filters
- Compound index field order: equality fields first, range/sort fields last
- Text index for full-text search fields: `@TextIndexed` on the field
- Aggregation pipeline over app-side joins — never load a full collection to filter in Java
- Never use `findAll()` without a filter on large collections — always paginate or stream

→ Detail on demand: `docs/context/mongodb-patterns.md` (indexes, aggregation pipeline).

---

## Database conventions

### Audit columns — every table must include
`created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `deleted_at TIMESTAMPTZ NULL`.
Soft-delete: set `deleted_at = now()` — never `DELETE`. All queries filter `WHERE deleted_at IS NULL`.
@docs/context/database-patterns.md

---

## Testing

### Structure
- Unit: JUnit 5 + AssertJ — no Mockito on domain logic, real objects only
- Integration: Testcontainers — always extend `AbstractIntegrationTest`
- Contract: Spring Cloud Contract — stubs published to Maven local on producer build
- Coverage gate: 80% line · 100% on domain model

### Naming
`should_<expectedBehavior>_when_<condition>`
e.g. `should_throwOrderNotFoundException_when_orderIdDoesNotExist`

Extend `AbstractIntegrationTest` from `common-test` — never redeclare containers. All four containers (PG, Mongo, Redis, Kafka) started once per suite.
@.claude/context/testcontainers-patterns.md

### Never
- H2 or EmbeddedMongo in integration tests — always Testcontainers
- Mock the database or cache layer in integration tests
- `Thread.sleep()` — use Awaitility: `await().atMost(10, SECONDS).until(...)`
- `spring.flyway.enabled=false` in test profiles — tests must validate prod migrations

---

## CI/CD

### GitHub Actions
- PR: `test` + `build` + `checkstyle`
- Merge to `main`: `build` → `docker push` → `deploy-staging`
- Image tag: `<service>:<git-sha>` — never `:latest` in K8s manifests

### Jenkins
- Nightly: full regression + contract verification
- Shared library: `/jenkins-shared`

### Secrets
- Never in code, Dockerfiles, or `application.yml`
- GitHub Actions secrets → K8s secrets → Spring `${ENV_VAR}`

---

## Docker

Multi-stage build: `eclipse-temurin:25-jdk` → `eclipse-temurin:25-jre`. Non-root user. Explicit artifact name (no `*.jar` glob). HEALTHCHECK mandatory.
→ Detail on demand: `docs/context/docker-patterns.md` (multi-stage template).

---

## Verify — run after every change, do not stop until green

```bash
./mvnw clean verify -pl <module> -am      # build + test
./mvnw checkstyle:check                   # lint
./mvnw flyway:validate -pl <module>       # migration drift
docker build --target build .             # dockerfile sanity
```

Fix root causes. Never suppress errors. Never skip tests to pass a build.

---

## Project layout
Monorepo: business services (PG) + <service-name> (Mongo) + api-gateway (WebFlux) + common-events/common-test.
Each module may have its own `CLAUDE.md`. Claude config in `.claude/`; docs in `docs/`.
@docs/context/project-layout.md

---

## Never
- `@Data` on JPA entities or domain objects with business logic
- `@ToString` / `@EqualsAndHashCode` on JPA entities with associations
- `@SuppressWarnings` to hide compile/lint failures
- `Optional.get()` without guard — use `orElseThrow()`
- `spring.jpa.hibernate.ddl-auto=create` or `update` — Flyway owns the schema
- Edit a committed Flyway migration — create a new version
- `spring.flyway.enabled=false` in any profile
- Commit secrets, tokens, or passwords
- H2 / EmbeddedMongo in integration tests
- Add a dependency without declaring version in root `pom.xml` BOM
- `@Transactional` on controllers or repository interfaces
- `ThreadLocal` — use `ScopedValue` on virtual threads
- `*.jar` glob in Dockerfile COPY — use explicit artifact name
- `git add -A` in automation — stage explicit paths or use `git add -p`
- Java serialization for Redis values — always Jackson JSON
- Immortal Redis keys — always set TTL
- Classes instead of records for immutable DTOs, commands, responses, and value objects — use records
- `@Value`+`@Builder` when a plain record suffices
- Reactive types (`Mono`, `Flux`, WebFlux) in non-gateway services — prefer WebMVC; WebFlux is reserved for api-gateway and streaming endpoints only
- Null fields in API responses — configure Jackson `NON_NULL` globally
- Raw `Page<Entity>` in API responses — always map to `PageResponse<RecordType>`
- Catch `BusinessException` subclasses and rethrow as `RuntimeException` — let `@ControllerAdvice` handle
- Bean Validation on service layer params — constraints belong on record components and controller params
- Hard-delete business data — always soft-delete via `deleted_at = now()`
- Avro field without `"default"` — breaks backward compatibility
- Remove, rename, or change type of existing Avro field — add a new field instead
- Produce Kafka messages before registering the schema in Schema Registry
- POST/PUT/PATCH endpoints that mutate state without `Idempotency-Key` support
- Outbound HTTP calls without `@CircuitBreaker` + `@Bulkhead` annotations

---

## Runbook

Common incident commands:

```bash
# Find trace across services
grep '"traceId":"<id>"' /var/log/<service>/app.log | jq .

# Replay a DLT message
kafka-console-consumer --topic order.payment.completed.DLT --from-beginning \
  | kafka-console-producer --topic order.payment.completed

# Flush a Redis key
redis-cli DEL "<service-name>:order:<uuid>"

# Flyway repair (after failed migration)
./mvnw flyway:repair -pl <module>
./mvnw flyway:migrate -pl <module>

# Check Kafka consumer lag
kafka-consumer-groups --describe --group <service-name>-group \
  --bootstrap-server localhost:9092

# Check schema registry compatibility
curl http://localhost:8081/compatibility/subjects/order.payment.completed-value/versions/latest \
  -d @common-events/src/main/avro/order/PaymentCompletedEvent.avsc \
  -H "Content-Type: application/json"
```

---

## Context management

### When to compact or clear
- `/compact` — run proactively after completing a feature and before starting the next one; never wait for auto-compact
- `/clear` — between unrelated tasks (e.g. "fix order retry bug" → "add catalog search"); carry-over context degrades reasoning
- `/effort high` — architecture decisions, debugging race conditions, migration planning on live tables
- `/effort low` — simple edits, renaming, adding a field, fixing a typo

### After /compact
Claude reads `.claude/session-checkpoint.md` (auto-written by `session-checkpoint.sh` hook) to resume thread without losing context.

### Signs context quality is degrading
- Claude re-asks questions already answered earlier in the session
- Claude proposes decisions already rejected (check `docs/decisions.md`)
- Claude generates code inconsistent with earlier choices
→ Run `/compact` or `/clear` immediately.

### Writing back to MEMORY.md
After resolving any non-obvious issue — a workaround, an unexpected environment behaviour, a subtle JPA/Kafka/Redis interaction — append a one-liner to `MEMORY.md` under `## Solved problems`:
`- [YYYY-MM] <module>: <what was wrong> → <what fixed it>`

---

## Agents

**Slash commands** (invoke explicitly with `/`):

| Command | Skill file | Purpose |
|---|---|---|
| `/write $ARGUMENTS` | `skills/write/` | Explore → plan → implement → verify |
| `/review` | `skills/review/` | Audit diff; Critical / Warning / Suggestion |
| `/commit` | `skills/commit/` | Gates → Conventional Commit → PR draft |
| `/test $ARGUMENTS` | `skills/test/` | Write/fix tests; coverage gate |
| `/migrate $DESCRIPTION` | `skills/migrate/` | Plan, write, validate Flyway migration |

**Sub-agents** (auto-invoked by Claude from description; can also call explicitly):

| Agent | File | Purpose |
|---|---|---|
| code-writer | `agents/code-writer.md` | Feature implementation |
| code-reviewer | `agents/code-reviewer.md` | Code review |
| git-agent | `agents/git-agent.md` | Commit + PR |
| test-agent | `agents/test-agent.md` | Test writing + coverage |
| scaffold-agent | `agents/scaffold-agent.md` | New service bootstrap |
| debug-agent | `agents/debug-agent.md` | Incident investigation (read-only) |
| performance-agent | `agents/performance-agent.md` | Latency/capacity investigation (read-only) |

Skills live in `.claude/skills/<name>/SKILL.md`. See each file for full instructions.
