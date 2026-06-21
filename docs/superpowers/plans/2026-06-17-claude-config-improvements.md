# Claude Config Improvements — All Categories to 9.5+ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise all Claude Code configuration categories from their current scores (8.0–9.0) to ≥ 9.5/10 by adding missing behavioural rules, documentation, and agent/MCP improvements.

**Architecture:** All changes are markdown, shell script (bash), and JSON — no Java compilation, no Flyway, no tests. The implementation order respects dependencies: CLAUDE.md behavioural rules first (they are referenced by agents and hooks), then documentation, then tooling (MCP, SETUP, new agent).

**Tech Stack:** Markdown, Bash, JSON. Python inline in bash for safe MEMORY.md section replacement on Windows.

## Global Constraints

- British English for all prose and comments.
- No `// TODO` without a ticket reference.
- All file paths are relative to repo root (`D:\IdeaProjects\claude-template`).
- Every file must end with a trailing newline.
- Preserve existing content in files being modified — only add or replace the specific section called for.
- Follow existing formatting patterns in each file (heading levels, table alignment, code fence style).

---

### Task 1: Add ambiguity handling policy to `.claude/CLAUDE.md`

**Files:**
- Modify: `.claude/CLAUDE.md` (after line 14, after the `## Output preferences` section)

**Interfaces:**
- Consumes: nothing
- Produces: `## Ambiguity handling` section in `.claude/CLAUDE.md` — referenced by Tasks 2 (agent updates) and all future agent invocations

- [ ] **Step 1: Read current file to confirm insertion point**

Open `.claude/CLAUDE.md`. Confirm `## Output preferences` ends at line 14. The new section goes after line 14, before `## Session behaviour`.

- [ ] **Step 2: Add the ambiguity handling section**

Insert the following block between `## Output preferences` (line 14) and `## Session behaviour` (line 16):

```markdown

## Ambiguity handling

Three-tier policy for all agents and skills:

| Tier | When to apply | Action |
|---|---|---|
| **Assume and state** | Implementation details: package name, variable name, field type, default value, method visibility | Pick the CLAUDE.md-compliant default; state it in one sentence at the top of the response; proceed immediately |
| **Ask first** | Scope decisions: new table vs JSONB, new service vs existing, sync REST vs async Kafka, endpoint shape/HTTP method, breaking vs non-breaking change | Stop. Ask **one** question. Write no code until answered. |
| **Flag and continue** | Minor convention gaps where CLAUDE.md has a clear default but the deviation is worth noting | Note inline as `[convention: using X because Y]`; apply the default; continue |

```

- [ ] **Step 3: Verify the file renders correctly**

Read `.claude/CLAUDE.md` and confirm:
- The new section appears between `## Output preferences` and `## Session behaviour`
- The table has 3 data rows (Assume and state, Ask first, Flag and continue)
- No existing content was lost

- [ ] **Step 4: Commit**

```bash
git add .claude/CLAUDE.md
git commit -m "docs: add ambiguity handling policy to .claude/CLAUDE.md"
```

---

### Task 2: Replace per-agent ambiguity rules with global policy reference

**Files:**
- Modify: `.claude/agents/code-writer.md` (lines 51–58, the `## Ambiguity` section)
- Modify: `.claude/agents/scaffold-agent.md` (lines 25–31, the `## Ambiguity` section)

**Interfaces:**
- Consumes: `## Ambiguity handling` section from Task 1 in `.claude/CLAUDE.md`
- Produces: shortened `## Ambiguity` sections in both agent files that delegate to the global policy

- [ ] **Step 1: Replace code-writer ambiguity section**

In `.claude/agents/code-writer.md`, replace lines 51–58 (the current `## Ambiguity` block) with:

```markdown
## Ambiguity

Follow the three-tier ambiguity policy in `.claude/CLAUDE.md § Ambiguity handling`.
For code-writer, "Ask first" triggers include: endpoint shape/HTTP method, new table vs JSONB,
new service vs existing, and Kafka event vs synchronous call.
```

- [ ] **Step 2: Replace scaffold-agent ambiguity section**

In `.claude/agents/scaffold-agent.md`, replace lines 25–31 (the current `## Ambiguity` block) with:

```markdown
## Ambiguity

Follow the three-tier ambiguity policy in `.claude/CLAUDE.md § Ambiguity handling`.
For scaffold-agent, "Ask first" triggers include: service name, database type (PG vs Mongo),
Kafka role (producer/consumer/both/none), and port assignment.
```

- [ ] **Step 3: Verify both files**

Read both files and confirm:
- Each has a `## Ambiguity` section
- Each references `.claude/CLAUDE.md § Ambiguity handling`
- No other sections were lost or damaged

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/code-writer.md .claude/agents/scaffold-agent.md
git commit -m "docs: replace per-agent ambiguity rules with global policy reference"
```

---

### Task 3: Add MEMORY.md write rule to `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (lines 440–447, inside the `## Context management` section, after the `### Signs context quality is degrading` subsection)

**Interfaces:**
- Consumes: nothing
- Produces: instruction in `CLAUDE.md` that directs Claude to write back to `MEMORY.md` after resolving non-obvious issues

- [ ] **Step 1: Add the write rule**

In `CLAUDE.md`, insert the following block after line 447 (after the `→ Run /compact or /clear immediately.` line) and before the `---` separator on line 449:

```markdown

### Writing back to MEMORY.md
After resolving any non-obvious issue — a workaround, an unexpected environment behaviour, a subtle JPA/Kafka/Redis interaction — append a one-liner to `MEMORY.md` under `## Solved problems`:
`- [YYYY-MM] <module>: <what was wrong> → <what fixed it>`
```

- [ ] **Step 2: Verify the section**

Read `CLAUDE.md` around line 448 and confirm the new subsection sits inside `## Context management`, after the degradation signs and before the `---` separator that precedes `## Agents`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add MEMORY.md write rule to context management section"
```

---

### Task 4: Extend `session-checkpoint.sh` to sync active work to MEMORY.md

**Files:**
- Modify: `.claude/hooks/session-checkpoint.sh`

**Interfaces:**
- Consumes: `MEMORY.md` in repo root (the `## Active work` section)
- Produces: updated `## Active work` section in `MEMORY.md` on every session stop — all other sections untouched

- [ ] **Step 1: Add Python block to session-checkpoint.sh**

Append the following block to `.claude/hooks/session-checkpoint.sh`, before the final `exit 0` line (currently line 29). This uses Python (available on Windows via `py` or `python3`) to safely replace only the `## Active work` section:

```bash

# --- Sync ## Active work section in MEMORY.md ---
MEMORY_FILE="$REPO_ROOT/MEMORY.md"
if [ -f "$MEMORY_FILE" ]; then
  python3 -c "
import re, sys

memory_path = sys.argv[1]
branch = sys.argv[2]
uncommitted = sys.argv[3]

with open(memory_path, 'r', encoding='utf-8') as f:
    content = f.read()

file_list = uncommitted.strip()
if file_list:
    bullet_lines = '\n'.join(f'- {line}' for line in file_list.splitlines())
    new_section = f'## Active work\n- Branch: \`{branch}\`\n{bullet_lines}\n'
else:
    new_section = f'## Active work\n- Branch: \`{branch}\`\n- No uncommitted files\n'

# Replace content between ## Active work and the next ## header (or EOF)
pattern = r'## Active work\n.*?(?=\n## |\Z)'
if re.search(pattern, content, re.DOTALL):
    content = re.sub(pattern, new_section.rstrip(), content, count=1, flags=re.DOTALL)
else:
    content = content.rstrip() + '\n\n' + new_section

with open(memory_path, 'w', encoding='utf-8') as f:
    f.write(content)
" "$MEMORY_FILE" "$BRANCH" "$UNCOMMITTED" 2>/dev/null && \
  echo "MEMORY.md ## Active work section updated" >&2 || \
  echo "MEMORY.md update skipped (Python not available or error)" >&2
fi
```

- [ ] **Step 2: Verify the full script**

Read `.claude/hooks/session-checkpoint.sh` end-to-end and confirm:
- The existing checkpoint logic (lines 1–28) is unchanged
- The new Python block appears before `exit 0`
- The script still exits cleanly with `exit 0` at the end

- [ ] **Step 3: Test the script locally**

```bash
bash .claude/hooks/session-checkpoint.sh
```

Expected: no errors. Check that `.claude/session-checkpoint.md` was written and that `MEMORY.md`'s `## Active work` section now contains the current branch name.

- [ ] **Step 4: Commit**

```bash
git add .claude/hooks/session-checkpoint.sh
git commit -m "feat: extend session-checkpoint.sh to sync active work to MEMORY.md"
```

---

### Task 5: Create `docs/context/security.md`

**Files:**
- Create: `docs/context/security.md`

**Interfaces:**
- Consumes: nothing
- Produces: `docs/context/security.md` — imported by `CLAUDE.md` in Task 6

- [ ] **Step 1: Create the security context file**

Write `docs/context/security.md` with the following content:

```markdown
# Spring Security patterns

## SecurityFilterChain bean — stateless, CSRF disabled
```java
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(AbstractHttpConfigurer::disable)
            .sessionManagement(s -> s.sessionCreationPolicy(STATELESS))
            .authorizeHttpRequests(a -> a
                .requestMatchers("/actuator/health").permitAll()
                .anyRequest().authenticated())
            .build();
    }
}
```

## @PreAuthorize on service layer
```java
@EnableMethodSecurity // on SecurityConfig class
// then on service methods — never on controllers:
@PreAuthorize("hasRole('ADMIN')")
public void cancelOrder(UUID orderId) { ... }
```

## Header-based identity — reading gateway-injected headers
```java
@Component
public class UserContextFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res,
                                    FilterChain chain) throws ServletException, IOException {
        String userId = req.getHeader("X-User-Id");
        String roles  = req.getHeader("X-User-Roles");
        // Store in ScopedValue or pass via method params — never ThreadLocal
        chain.doFilter(req, res);
    }
}
```

## MDC integration — traceId + userId
```java
@Component
public class MdcRequestFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res,
                                    FilterChain chain) throws ServletException, IOException {
        try {
            MDC.put("traceId", req.getHeader("traceparent"));
            MDC.put("userId", req.getHeader("X-User-Id"));
            MDC.put("serviceId", "<service-name>");
            chain.doFilter(req, res);
        } finally {
            MDC.clear();
        }
    }
}
```

## Rules
- Never rely on Spring Boot auto-config defaults — always declare a `SecurityFilterChain` bean
- `@PreAuthorize` on service layer only — never on controllers
- Stateless session management — no HTTP session
- Actuator health endpoint open (`permitAll`); details `when-authorized`
- `X-User-Id` / `X-User-Roles` trusted from gateway — no re-validation in downstream services
```

- [ ] **Step 2: Verify the file**

Read `docs/context/security.md` and confirm it contains all four sections (SecurityFilterChain, PreAuthorize, header-based identity, MDC integration) plus the Rules section.

- [ ] **Step 3: Commit**

```bash
git add docs/context/security.md
git commit -m "docs: add Spring Security context patterns"
```

---

### Task 6: Add `@docs/context/security.md` import to `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (line 60, after the Spring Security subsection)

**Interfaces:**
- Consumes: `docs/context/security.md` from Task 5
- Produces: import reference in `CLAUDE.md` so Claude loads the security patterns on demand

- [ ] **Step 1: Add the import reference**

In `CLAUDE.md`, insert the following line after line 60 (after `- Method security (@PreAuthorize) on service layer, not controller`), before the blank line that precedes `### Jackson`:

```markdown
@docs/context/security.md
```

- [ ] **Step 2: Verify**

Read `CLAUDE.md` lines 57–65 and confirm `@docs/context/security.md` appears on its own line between the last Spring Security bullet and `### Jackson`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add security.md import reference to CLAUDE.md"
```

---

### Task 7: Create `docs/sagas/_template.md`

**Files:**
- Create: `docs/sagas/_template.md`

**Interfaces:**
- Consumes: nothing
- Produces: `docs/sagas/_template.md` — the saga documentation template; git tracks the directory via this file

- [ ] **Step 1: Create the directory and template**

```bash
mkdir -p docs/sagas
```

Write `docs/sagas/_template.md` with the following content:

```markdown
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

- [ ] **Step 2: Verify**

Read `docs/sagas/_template.md` and confirm it matches the structure above. Confirm `docs/sagas/` directory exists.

- [ ] **Step 3: Commit**

```bash
git add docs/sagas/_template.md
git commit -m "docs: add saga documentation template and directory"
```

---

### Task 8: Append 3 missing decisions to `decisions.md`

**Files:**
- Modify: `docs/decisions.md` (append rows to the existing table)

**Interfaces:**
- Consumes: nothing
- Produces: 3 new rows in the decision log table

- [ ] **Step 1: Append the three decision rows**

Add the following three rows to the end of the table in `docs/decisions.md` (after the last `|` row, currently the Resilience4j row):

```markdown
| 2025-06 | Virtual threads (Java 25 default) over platform threads | Reactive WebFlux everywhere | Simplifies code; `ScopedValue` replaces `ThreadLocal`; Spring Boot 4 native; no reactive complexity outside api-gateway |
| 2025-06 | Resilience4j defaults as documented (50%/2s/30s/5 calls/10 concurrent/5s timeout) | Per-service customisation from day one | Sane starting point; services override in `application.yml` only when measured data demands it |
| 2025-06 | Idempotency key scoped to service, never per-user | Per-user idempotency key | Prevents cross-user replay; keeps idempotency purely about network retries, not authorisation |
```

- [ ] **Step 2: Verify**

Read `docs/decisions.md` and confirm the table now has 13 rows (10 original + 3 new). Confirm the new rows appear at the bottom and the table formatting is consistent.

- [ ] **Step 3: Commit**

```bash
git add docs/decisions.md
git commit -m "docs: add virtual threads, resilience4j defaults, and idempotency scope decisions"
```

---

### Task 9: Add `universal_servers` and `note` to `.claude/mcp.json`

**Files:**
- Modify: `.claude/mcp.json` (the `"usage"` object, starting at line 40)

**Interfaces:**
- Consumes: nothing
- Produces: updated `usage` block with `universal_servers` and `note` keys

- [ ] **Step 1: Update the usage block**

In `.claude/mcp.json`, replace the current `"usage"` object (lines 40–50) with:

```json
  "usage": {
    "universal_servers": ["context7"],
    "note": "context7 applies to all modules — omitted from module_mapping for brevity",
    "how_to_activate": "Add server names to .claude/settings.json under 'mcpServers' or use Claude Code's /mcp command.",
    "module_mapping": {
      "api-gateway":     ["github"],
      "<service-name>":  ["github", "postgres", "jira"],
      "common-events":   ["github", "schema-registry"]
    }
  }
```

- [ ] **Step 2: Validate JSON**

```bash
python3 -c "import json; json.load(open('.claude/mcp.json'))" && echo "Valid JSON"
```

Expected: `Valid JSON`

- [ ] **Step 3: Commit**

```bash
git add .claude/mcp.json
git commit -m "docs: add universal_servers and note to mcp.json usage block"
```

---

### Task 10: Add context7 activation and setup verification to `SETUP.md`

**Files:**
- Modify: `SETUP.md` (append two new sections at the end)

**Interfaces:**
- Consumes: nothing
- Produces: context7 setup instructions and a "Verify your setup" checklist in `SETUP.md`

- [ ] **Step 1: Add context7 entry and verification section**

Append the following to the end of `SETUP.md`:

```markdown

## context7 — live library docs

No environment variable or token required. Activates automatically from `.claude/mcp.json` on session start.

Manual activation:
```bash
claude mcp add context7 -- npx -y @upstash/context7-mcp@latest
```

## Verify your setup

After cloning and configuring, confirm these three things work:

1. **Start Claude Code** → confirm `inject-git-context.sh` fires (branch name appears in session context)
2. **Edit any `.java` file** → confirm checkstyle hook output appears in the turn
3. **Run `/review`** → confirm the review skill loads and outputs the checklist header
```

- [ ] **Step 2: Verify**

Read `SETUP.md` and confirm:
- The `## context7` section appears after `## MCP setup`
- The `## Verify your setup` section appears at the bottom
- The verification checklist has 3 numbered items

- [ ] **Step 3: Commit**

```bash
git add SETUP.md
git commit -m "docs: add context7 activation and setup verification to SETUP.md"
```

---

### Task 11: Create the performance agent

**Files:**
- Create: `.claude/agents/performance-agent.md`
- Modify: `CLAUDE.md` (the agents table, around line 471)

**Interfaces:**
- Consumes: `debug-agent.md` structure as a template (same read-only, same output format, similar allowed tools)
- Produces: `.claude/agents/performance-agent.md` — a new read-only agent for latency/capacity investigation; updated agents table in `CLAUDE.md`

- [ ] **Step 1: Create the performance agent file**

Write `.claude/agents/performance-agent.md`:

```markdown
---
name: performance-agent
description: >
  Latency and capacity investigation agent for this Java 25 / Spring Boot 4 microservice project.
  Invoke when a service has high p99 latency, a Kafka consumer lag is growing, a circuit breaker
  keeps opening under load, Redis hit rate is low, or JPA N+1 queries are suspected.
  This agent ONLY investigates and reports — it never modifies source code or commits anything.
  Use code-writer to fix after performance-agent identifies the bottleneck.
allowed-tools:
  - Bash(git *)
  - Bash(grep *)
  - Bash(cat *)
  - Bash(redis-cli *)
  - Bash(kafka-* *)
  - Bash(curl *)
  - Bash(docker *)
  - Bash(./mvnw *)
  - Read
  - Grep
---

You are the **performance-agent**. Your sole responsibility is to investigate latency,
throughput, and capacity issues and produce a clear bottleneck report. You never modify
source code, never commit, and never run destructive commands.

## Trigger examples
- "<service-name> p99 latency is 4s — investigate"
- "Kafka consumer lag on <service-name>-group keeps growing"
- "inventory circuit breaker keeps opening under load"
- "Redis hit rate is low — why?"
- "<service-name> search is slow under concurrent requests"

## Ambiguity

Follow the three-tier ambiguity policy in `.claude/CLAUDE.md § Ambiguity handling`.
If the symptom is vague, ask one question: "Which service, environment, and metric or symptom
are you seeing?" before investigating.

## Investigation playbook

### HTTP latency
```bash
# Check p99/p95 latency via actuator
curl -s http://localhost:<port>/actuator/metrics/http.server.requests | jq '.measurements'
curl -s http://localhost:<port>/actuator/metrics/http.server.requests?tag=uri:<path> | jq '.'
# JVM heap and thread count
curl -s http://localhost:<port>/actuator/metrics/jvm.memory.used | jq '.measurements'
curl -s http://localhost:<port>/actuator/metrics/jvm.threads.live | jq '.measurements'
# GC pause time
curl -s http://localhost:<port>/actuator/metrics/jvm.gc.pause | jq '.measurements'
```

### Circuit breaker state
```bash
curl -s http://localhost:<port>/actuator/circuitbreakers | jq '.circuitBreakers'
curl -s http://localhost:<port>/actuator/health | jq '.components.circuitBreakers'
# Distinguish slow-call rate from failure rate
curl -s http://localhost:<port>/actuator/metrics/resilience4j.circuitbreaker.slow.call.rate | jq '.'
curl -s http://localhost:<port>/actuator/metrics/resilience4j.circuitbreaker.failure.rate | jq '.'
```

### Kafka consumer lag
```bash
kafka-consumer-groups --describe --group <service>-group \
  --bootstrap-server ${KAFKA_BOOTSTRAP_SERVERS:-localhost:9092}
# DLT message count
kafka-console-consumer --topic <topic>.DLT --from-beginning --max-messages 5 \
  --bootstrap-server ${KAFKA_BOOTSTRAP_SERVERS:-localhost:9092} 2>/dev/null | wc -l
# Consumer offset lag over time
kafka-consumer-groups --describe --group <service>-group \
  --bootstrap-server ${KAFKA_BOOTSTRAP_SERVERS:-localhost:9092} | awk '{print $6}'
```

### Redis efficiency
```bash
redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"
# Calculate hit rate: hits / (hits + misses)
redis-cli INFO memory | grep -E "used_memory_human|maxmemory_human"
# Check TTLs on hot keys
redis-cli KEYS "<service>:<entity>:*" | head -10 | while read key; do
  echo "$key TTL=$(redis-cli TTL "$key")"
done
```

### JPA / N+1 detection
```bash
# Enable Hibernate statistics via actuator (if configured)
curl -s http://localhost:<port>/actuator/metrics/hibernate.query.executions | jq '.'
curl -s http://localhost:<port>/actuator/metrics/hibernate.sessions.open | jq '.'
# Check slow query log (PostgreSQL)
docker exec <pg-container> psql -U postgres -c \
  "SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"
# Grep for lazy loading warnings in logs
grep -i "HHH90003004" /var/log/<service>/app.log | tail -20
```

## Output format

```
## Performance Report

### Symptom
<what was reported — include metric values>

### Investigation steps taken
1. <command run> → <finding with numbers>
2. ...

### Bottleneck identified
<precise description of the performance issue and why it occurs>

### Evidence
<metric values, log lines, Redis stats — quoted verbatim>

### Recommended fix
<what code-writer or the developer should change — no code written here>

### Affected files (suspected)
- <path>: <reason>
```

## Invariants
- Never modify source code, migrations, or configs
- Never restart services or containers
- Never delete Redis keys or Kafka messages
- Always quote evidence verbatim — never paraphrase metrics
- If bottleneck cannot be determined, list all investigated angles and what to try next
- Compare observed values against SLO defaults from CLAUDE.md (50% failure rate, 2s slow call, 5s timeout)
```

- [ ] **Step 2: Add performance-agent to the agents table in CLAUDE.md**

In `CLAUDE.md`, add a new row to the `**Sub-agents**` table (after the `debug-agent` row at line 472):

```markdown
| performance-agent | `agents/performance-agent.md` | Latency/capacity investigation (read-only) |
```

- [ ] **Step 3: Verify both files**

Read `.claude/agents/performance-agent.md` and confirm it has:
- Frontmatter with `name: performance-agent` and `allowed-tools` matching debug-agent
- Five playbook sections (HTTP latency, circuit breaker, Kafka lag, Redis, JPA/N+1)
- Output format section
- Invariants section

Read `CLAUDE.md` agents table and confirm `performance-agent` appears as the last row.

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/performance-agent.md CLAUDE.md
git commit -m "feat: add performance-agent for latency/capacity investigation"
```

---

## Self-Review Checklist

### Spec coverage

| Spec section | Task |
|---|---|
| 1a. Ambiguity policy in `.claude/CLAUDE.md` | Task 1 |
| 1b. Agent ambiguity references | Task 2 |
| 1c. MEMORY.md write rule | Task 3 |
| 1d. session-checkpoint.sh MEMORY.md sync | Task 4 |
| 2a. `docs/context/security.md` | Task 5 |
| 2a (import). Security.md import in CLAUDE.md | Task 6 |
| 2b. `docs/sagas/_template.md` | Task 7 |
| 2c. 3 missing decision log entries | Task 8 |
| 3a. mcp.json `universal_servers` | Task 9 |
| 3b. SETUP.md context7 + verification | Task 10 |
| 3c. performance-agent | Task 11 |

All spec sections covered. No gaps.

### Placeholder scan
No TBD, TODO, "implement later", "similar to Task N", or description-without-code steps found.

### Type/name consistency
- `## Ambiguity handling` — consistent in Task 1 (creation) and Task 2 (reference as `.claude/CLAUDE.md § Ambiguity handling`)
- `## Active work` — consistent in Task 4 (Python regex matches the header in `MEMORY.md`)
- `performance-agent` — consistent in Task 11 (file name, frontmatter `name:`, and CLAUDE.md table entry)
- `docs/context/security.md` — consistent in Task 5 (creation) and Task 6 (import as `@docs/context/security.md`)
