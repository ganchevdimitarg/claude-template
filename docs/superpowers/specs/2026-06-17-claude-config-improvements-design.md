# Design: Claude Config Improvements — All Categories to 9.5+

**Date:** 2026-06-17
**Status:** Approved
**Goal:** Raise all Claude Code configuration categories from their current scores to ≥ 9.5/10.

---

## Current Scores & Targets

| Category | Current | Target | Gap |
|---|---|---|---|
| `.claude/CLAUDE.md` (personal) | 8.0 | 9.5 | −1.5 |
| `MEMORY.md` | 8.0 | 9.5 | −1.5 |
| Agents | 9.0 | 9.5 | −0.5 |
| MCP Servers | 9.0 | 9.5 | −0.5 |
| `docs/` context + ADRs | 9.0 | 9.5 | −0.5 |
| `decisions.md` | 9.0 | 9.5 | −0.5 |
| `SETUP.md` | 9.0 | 9.5 | −0.5 |

Categories already at 9.5 (`CLAUDE.md` master, Skills, Hooks) are out of scope.

---

## Section 1: Behavioral Rules

### 1a. `.claude/CLAUDE.md` — Ambiguity policy

Add a new `## Ambiguity handling` section establishing a project-wide three-tier policy. This replaces the scattered, inconsistent per-agent ambiguity rules (each agent currently defines its own approach).

**Three tiers:**

| Tier | When to apply | Action |
|---|---|---|
| **Assume and state** | Implementation details: package name, variable name, field type, default value, method visibility | Pick the CLAUDE.md-compliant default; state it in one sentence at the top of the response; proceed immediately |
| **Ask first** | Scope decisions: new table vs JSONB, new service vs existing, sync REST vs async Kafka, endpoint shape/HTTP method, breaking vs non-breaking change | Stop. Ask **one** question. Write no code until answered. |
| **Flag and continue** | Minor convention gaps where CLAUDE.md has a clear default but the deviation is worth noting | Note inline as `[convention: using X because Y]`; apply the default; continue |

**Placement:** New `## Ambiguity handling` section in `.claude/CLAUDE.md`, after `## Output preferences`.

---

### 1b. `CLAUDE.md` — MEMORY.md write rule

Add to the existing `## Context management` section (after the `/compact` guidance):

> After resolving any non-obvious issue — a workaround, an unexpected environment behaviour, a subtle JPA/Kafka/Redis interaction — append a one-liner to `MEMORY.md` under `## Solved problems`:
> `- [YYYY-MM] <module>: <what was wrong> → <what fixed it>`

This closes the read/write loop. Claude already reads `MEMORY.md` at session start (per existing `.claude/CLAUDE.md` rule); this instruction ensures knowledge is written back without requiring a separate `/memory` command.

---

### 1c. `session-checkpoint.sh` — Active work sync to MEMORY.md

Currently the Stop hook writes `session-checkpoint.md` with branch + recent commits + uncommitted files.

**Extension:** After writing `session-checkpoint.md`, the script also overwrites the `## Active work` section of `MEMORY.md` with the current git state (branch + uncommitted file list). All other MEMORY.md sections (project facts, solved problems, team preferences) are left untouched.

**Implementation:** Use Python to read `MEMORY.md`, replace the content between `## Active work` and the next `##` header, write back. This is safe on Windows (no `sed -i` dependency) and consistent with the other hooks' Python inline approach.

---

## Section 2: Documentation Additions

### 2a. `docs/context/security.md`

New context file following the established pattern (code example → rules). Covers the four Spring Security patterns referenced in `CLAUDE.md` that have no dedicated example file:

1. **`SecurityFilterChain` bean** — stateless, CSRF disabled, actuator health permitted, all else authenticated
2. **`@PreAuthorize` on service layer** — with `@EnableMethodSecurity`; annotated on service method, not controller
3. **Header-based identity** — reading `X-User-Id` / `X-User-Roles` from gateway-injected headers via a filter or resolver
4. **MDC integration** — `MdcRequestFilter` setting `userId` from `X-User-Id` alongside `traceId`

Rules section: no Spring Boot auto-config defaults, `@PreAuthorize` on service layer only, stateless session, actuator health open / details `when-authorized`.

Referenced from `CLAUDE.md` via `@docs/context/security.md` (same pattern as existing context imports).

---

### 2b. `docs/sagas/` directory + `_template.md`

`CLAUDE.md` directs saga documentation to `docs/sagas/<name>.md` but the directory does not exist.

**Create:**
- `docs/sagas/_template.md` — saga documentation template (see structure below)

Git tracks the directory via this file. Actual saga docs are created as siblings when flows are designed.

**Template structure:**
```
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
```

---

### 2c. `decisions.md` — 3 missing entries

Three load-bearing decisions referenced throughout `CLAUDE.md` that have no log entry:

| Date | Decision | Alternative rejected | Reason |
|---|---|---|---|
| 2025-06 | Virtual threads (Java 25 default) over platform threads | Reactive WebFlux everywhere | Simplifies code; `ScopedValue` replaces `ThreadLocal`; Spring Boot 4 native; no reactive complexity outside api-gateway |
| 2025-06 | Resilience4j defaults as documented (50% / 2s / 30s / 5 calls / 10 concurrent / 5s timeout) | Per-service customisation from day one | Sane starting point; services override in `application.yml` only when measured data demands it |
| 2025-06 | Idempotency key scoped to service, never per-user | Per-user idempotency key | Prevents cross-user replay; keeps idempotency purely about network retries, not authorisation |

---

## Section 3: MCP, SETUP, and Performance Agent

### 3a. `mcp.json` — context7 in `usage` block

Add `"universal_servers"` and `"note"` keys to the `usage` object. This is cleaner than duplicating `"context7"` across every module array and avoids implying it is module-specific:

```json
"usage": {
  "universal_servers": ["context7"],
  "note": "context7 applies to all modules — omitted from module_mapping for brevity",
  "module_mapping": { ... unchanged ... }
}
```

---

### 3b. `SETUP.md` — context7 activation + setup verification

**context7 entry** in the MCP setup section (no env var needed):
```bash
# context7 — live library docs (no env var or token required)
claude mcp add context7 -- npx -y @upstash/context7-mcp@latest
# Or activates automatically from .claude/mcp.json on next session start.
```

**New "Verify your setup" subsection** at the bottom of `SETUP.md`:
1. Start Claude Code → confirm `inject-git-context.sh` fires (branch name appears in session title / context)
2. Edit any `.java` file → confirm checkstyle hook output appears in the turn
3. Run `/review` → confirm the review skill loads and outputs the checklist header

---

### 3c. `.claude/agents/performance-agent.md`

New read-only agent for latency/capacity investigation. Mirrors `debug-agent` structure but triggered by slowness rather than failures.

**Trigger examples:**
- "order-service p99 latency is 4s — investigate"
- "Kafka consumer lag on notification-service-group keeps growing"
- "inventory circuit breaker keeps opening under load"
- "Redis hit rate is low — why?"

**Playbook sections** (each with ready-to-paste commands):
1. **HTTP latency** — actuator `/metrics` for `http.server.requests` percentiles, JVM heap, thread count
2. **Circuit breaker state** — actuator `/circuitbreakers`, slow-call rate vs failure rate distinction
3. **Kafka consumer lag** — `kafka-consumer-groups --describe`, DLT message count
4. **Redis efficiency** — `INFO stats` hit/miss ratio, `INFO memory`, TTL inspection on hot keys
5. **JPA / N+1** — Hibernate statistics via actuator, slow query log

**Output format:** Symptom → Steps taken → Bottleneck identified → Evidence (verbatim) → Recommended fix → Affected files. Never modifies source code.

**Allowed tools:** same read-only Bash patterns as `debug-agent` (`git *`, `grep *`, `curl *`, `redis-cli *`, `kafka-* *`, `docker *`, `./mvnw *`) plus `Read` and `Grep`.

---

## Implementation Order

Execute in this order to respect dependencies (CLAUDE.md rules before the hooks that support them):

1. `.claude/CLAUDE.md` — add ambiguity policy section
2. `.claude/agents/code-writer.md` + `.claude/agents/scaffold-agent.md` — replace per-agent ambiguity rules with a one-line reference to the global policy in `.claude/CLAUDE.md`
3. `CLAUDE.md` — add MEMORY.md write rule to context management section
4. `session-checkpoint.sh` — extend to overwrite MEMORY.md `## Active work` section
5. `docs/context/security.md` — new file
6. `CLAUDE.md` — add `@docs/context/security.md` import reference in the Spring Security section
7. `docs/sagas/_template.md` — new file
8. `decisions.md` — append 3 new rows
9. `.claude/mcp.json` — add `universal_servers` + `note` to `usage` block
10. `SETUP.md` — add context7 activation + verify section
11. `.claude/agents/performance-agent.md` — new file

**No build steps required.** All changes are markdown, shell script, and JSON — no Java compilation, no Flyway, no tests.
