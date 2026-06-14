---
name: review
description: Review staged or recent changes against project conventions. Triggers on /review.
allowed-tools: Bash(git diff *), Bash(git log *), Read, Grep
---

## Steps

1. Run: `git diff --staged` (pre-commit) or `git diff HEAD~1` (post-commit).
2. For each changed file apply the checklist below.
3. Output grouped by severity: Critical → Warning → Suggestion.
4. Never approve if any Critical item is present.

## Severity key
- **Critical**: security risk, data loss, broken build, schema corruption — block merge
- **Warning**: convention violation, maintainability issue, missing safety net — must fix before merge
- **Suggestion**: style, improvement, better pattern available — fix encouraged, not blocking

---

## Checklist

### Secrets & Safety [Critical]
- No secrets, tokens, API keys, or passwords in diff
- No `git add -A` in scripts — must stage explicit paths

### Lombok [Warning]
- No `@Data` on JPA entities or domain objects with business logic
- No `@ToString` or `@EqualsAndHashCode` on JPA entities with associations
- `@Slf4j` used for logging — no manual `Logger` declaration
- `@RequiredArgsConstructor` on Spring components — no `@Autowired`

### Java [Warning unless noted]
- Immutable DTOs, commands, responses, and event payloads use records — flag any `@Value`/`@Data` class that should be a record [Suggestion: propose the equivalent record]
- No `Optional.get()` without guard — must use `orElseThrow()` [Critical]
- No `@SuppressWarnings` hiding real errors [Warning]
- No `ThreadLocal` — use `ScopedValue` on virtual threads [Warning]
- No string concatenation in log statements — use `@Slf4j` parameterised logging [Suggestion]
- No `instanceof` chains — use sealed + exhaustive switch [Suggestion]
- `String.format()` or text blocks for multiline strings — no string templates (JEP 430 withdrawn) [Warning]

### Spring [Warning unless noted]
- `@Transactional` not on controllers or repository interfaces [Warning]
- `SecurityFilterChain` bean declared explicitly — no reliance on auto-config defaults [Warning]
- `@PreAuthorize` on service layer, not controller [Warning]
- WebFlux / reactive types (`Mono`, `Flux`) only in `api-gateway` or explicitly approved streaming endpoints — flag any other usage [Warning]

### Observability [Warning unless noted]
- Every new service or HTTP handler has an `OncePerRequestFilter` (WebMVC) setting `traceId`, `spanId`, `userId`, `serviceId` in MDC — and clears on exit [Warning]
- All outbound HTTP calls propagate `traceparent` header [Warning]
- Kafka producers set `traceId` and `correlationId` as message headers [Warning]
- Kafka consumers read MDC from message headers before processing, clear after [Warning]
- New significant actions have a `MeterRegistry` counter — name: `<service>.<entity>.<action>` [Suggestion]
- No plain-text log format — structured JSON (logstash-logback-encoder) only [Warning]
- `/actuator/health` exposed; details restricted to internal only [Suggestion]

### Flyway [Critical unless noted]
- Migration file named correctly: `V<n>__<description>.sql` — two underscores [Warning]
- No edits to existing committed migration files [Critical]
- `spring.jpa.hibernate.ddl-auto` is `validate` — not `create`/`update`/`create-drop` [Critical]
- `spring.flyway.enabled` is not `false` in any profile [Critical]
- Each migration is one logical change; index separate from table creation [Suggestion]
- New `CREATE TABLE` migration includes `created_at`, `updated_at`, `deleted_at` audit columns [Warning]

### Redis [Warning]
- No Java serialization — Jackson JSON only
- All keys follow `<service>:<entity>:<id>` pattern
- All keys have TTL set — no immortal keys [Critical]

### Avro / Schema Registry [Critical unless noted]
- New `KafkaTemplate` usage has a corresponding `.avsc` in `common-events/src/main/avro/` [Critical]
- New `@KafkaListener` usage deserializes using the generated Avro class, not plain JSON [Warning]
- Every new field in an `.avsc` has a `"default"` declared [Critical: omitting breaks backward compat]
- No field removed, renamed, or type-changed in an existing schema [Critical: breaks consumers]
- Schema subject follows `<topic>-value` naming convention [Warning]
- `common-events` build runs `schema-registry:register` — confirm in CI config [Warning]

### Kafka [Warning unless noted]
- Topic follows `<domain>.<entity>.<event>` pattern
- Consumer group follows `<service>-group` pattern
- `@RetryableTopic` configured with DLT [Critical: missing retry = silent message loss]
- `traceId` and `correlationId` set as message headers
- Idempotency guard via Redis `correlationId` check before processing

### Validation [Warning unless noted]
- `@Valid` present on all `@RequestBody` and `@PathVariable` controller params [Warning]
- Bean Validation constraints on record components, not service method params [Warning]
- Cross-field rules in record compact constructor, not service layer [Suggestion]
- No `ValidationException` thrown from service layer for inputs that could be a Bean Validation constraint [Suggestion]

### Pagination [Warning]
- Controller uses `@PageableDefault` — no hardcoded page/size params
- `Page<Entity>` never returned directly — must map to `Page<RecordType>` then `PageResponse.of()`
- Max page size enforced (`@Max(100)` or equivalent)

### Jackson [Warning]
- No `ObjectMapper` instantiated manually — use injected bean or `JacksonConfig` customizer
- No null fields in response records — Jackson configured `NON_NULL` globally
- No epoch-long date fields — ISO-8601 strings only

### Records [Suggestion]
- Any `@Value` class with only final fields and no framework constraint → convert to record
- When suggesting conversion, output the equivalent record inline

### Testing [Warning unless noted]
- Test names follow `should_<expectedBehavior>_when_<condition>`
- Integration tests extend `AbstractIntegrationTest` — not H2 or EmbeddedMongo [Critical]
- No `Thread.sleep()` — use Awaitility [Warning]
- `spring.flyway.enabled` not disabled in test profiles [Critical]

### Docker [Warning unless noted]
- `COPY` uses explicit artifact name — not `*.jar` glob [Warning]
- Image not tagged `:latest` in K8s manifests [Critical]
- Non-root `USER` declared [Warning]
- `HEALTHCHECK` present [Warning]

### Dependencies [Warning]
- New dependencies have version declared in root `pom.xml` BOM