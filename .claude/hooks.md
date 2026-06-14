# Claude Code Hooks

Lifecycle hooks that run automatically during every Claude Code session.
All hooks are wired in `.claude/settings.json`. Scripts live in `.claude/hooks/`.

Hooks use the following exit code contract:
- `exit 0` — allow; Claude continues normally
- `exit 2` — block; stderr is shown to Claude as the reason and it must correct course
- `stdout JSON` with `additionalContext` — inject feedback into Claude's context without blocking

---

## Hook lifecycle

```
SessionStart
    └─ inject-git-context.sh       ← orient Claude with branch/commit/module state

PreToolUse  (before every tool call)
    ├─ block-dangerous.sh          ← Bash: block rm -rf, force-push, DELETE without WHERE
    ├─ block-main-commit.sh        ← Bash: block git commit on main/develop
    ├─ protect-secrets.sh          ← Read|Write|Edit|Bash: block access to secrets files
    ├─ protect-migrations.sh       ← Write|Edit: block editing committed Flyway migrations
    └─ audit-log.sh (async)        ← Bash: append every command to .claude/audit.log

PostToolUse (after every tool call)
    ├─ checkstyle-on-save.sh       ← Write|Edit .java: run Checkstyle; feed violations back
    ├─ flyway-validate.sh          ← Write .sql: run flyway:validate; feed errors back
    ├─ avro-validate.sh            ← Write|Edit .avsc: validate schema JSON + defaults
    └─ warn-generated-files.sh     ← Write|Edit: warn if file is generated (target/, @Generated)

Stop        (before Claude finishes a turn)
    └─ verify-gate.sh              ← run ./mvnw clean verify; force Claude to fix if red
```

---

## Hooks reference

### `inject-git-context.sh` — SessionStart

**Purpose:** Injects current repo state at the start of every session. Claude arrives oriented
without burning tool calls to discover branch, module layout, or recent commits.

**Output injected:**
- Current branch name (also sets `sessionTitle`)
- Last 8 commits
- Uncommitted / untracked file counts
- Active Maven modules
- Issue number extracted from branch name (e.g. `feat/order-service-142-retry` → `Refs #142`)

**Config:**
```json
{ "matcher": "startup", "hooks": [{ "type": "command", "command": "...inject-git-context.sh" }] }
```

---

### `block-dangerous.sh` — PreToolUse · Bash

**Purpose:** Blocks destructive shell commands before Claude executes them. Enforces multiple
items from the project Never list deterministically rather than relying on instruction alone.

**Blocked patterns:**
| Pattern | Reason |
|---|---|
| `rm -rf` | Irreversible bulk deletion |
| `git push --force` to main/develop | Rewrites shared history |
| `git add -A` | Stages secrets and unintended files |
| `DROP TABLE` / `DROP DATABASE` / `TRUNCATE` | Schema destruction outside Flyway |
| `DELETE FROM <table>;` without WHERE | Unguarded full-table wipe |
| `docker rm/stop/kill $(docker ps ...)` | Bulk container teardown |

**Exit:** `2` on match; error written to stderr, shown to Claude as block reason.

---

### `block-main-commit.sh` — PreToolUse · Bash

**Purpose:** Blocks `git commit` when the current branch is `main`, `develop`, or `master`.
Claude must create a feature branch first.

**Message to Claude:**
```
Blocked: direct commits to 'main' are not permitted.
Create a feature branch first:
  git checkout -b <type>/<scope>-<short-desc>
```

---

### `protect-secrets.sh` — PreToolUse · Read|Write|Edit|Bash

**Purpose:** Blocks any tool operation whose target path matches known secrets file patterns.

**Blocked patterns:** `.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`,
`secrets.`, `credentials`, `id_rsa`, `id_ed25519`, `application-prod.yml`, `application-production.yml`

**Exit:** `2` on match with explanation and redirect to environment variables / secrets manager.

---

### `protect-migrations.sh` — PreToolUse · Write|Edit

**Purpose:** Blocks editing a Flyway migration file (`db/migration/V*.sql`) that already
exists in git history. New untracked migration files are always allowed.

**Detection:** Uses `git ls-files --error-unmatch` — if the file is tracked, it is committed
and therefore immutable.

**Message to Claude:**
```
Blocked: editing a committed Flyway migration is not permitted.
Committed migrations are immutable — create V<n+1>__<description>.sql instead.
```

---

### `audit-log.sh` — PreToolUse · Bash (async)

**Purpose:** Appends every shell command Claude runs to `.claude/audit.log` for traceability.
Runs async — zero latency impact on the agent loop.

**Log format:** `timestamp | session_id | branch | command`

```
2025-06-14T10:23:01Z  sess_abc123  feat/order-retry  ./mvnw clean verify -pl order-service -am
2025-06-14T10:23:45Z  sess_abc123  feat/order-retry  git diff --staged
```

**Note:** `.claude/audit.log` is gitignored by default. Add these lines to your `.gitignore`:

```gitignore
# Claude Code — local only; never commit
.claude/audit.log
.claude/settings.local.json
```

You can apply this in one command:
```bash
printf '\n# Claude Code — local only\n.claude/audit.log\n.claude/settings.local.json\n' >> .gitignore
```

---

### `checkstyle-on-save.sh` — PostToolUse · Write|Edit

**Purpose:** Runs Checkstyle immediately after Claude writes or edits a `.java` file.
Violations are injected as `additionalContext` so Claude fixes them in the same turn,
not at commit time.

**Module detection:** Extracts top-level directory from `file_path` and checks for `pom.xml`.
Skips if module cannot be determined.

**Feedback to Claude:**
```
Checkstyle violations found after editing order-service/src/.../OrderService.java:
[WARN] Line 42: 'if' construct must use '{}'s. [NeedBraces]
Fix these before proceeding.
```

---

### `flyway-validate.sh` — PostToolUse · Write

**Purpose:** Runs `flyway:validate` immediately after Claude writes a new `.sql` file under
`db/migration/`. Catches naming errors, duplicate version numbers, and checksum drift
before they reach CI.

**Feedback to Claude:**
```
Flyway validation failed after writing order-service/src/main/resources/db/migration/V5__add_index.sql:
Validate failed: Migration checksum mismatch for migration version 5
Check migration version, filename format (V<n>__<desc>.sql), and checksum.
```

---

### `avro-validate.sh` — PostToolUse · Write|Edit

**Purpose:** Validates Avro schema files (`.avsc`) after Claude creates or edits them.

**Checks performed:**
1. Valid JSON syntax
2. `type` is `"record"`
3. `name` is present
4. `namespace` is present (required for Schema Registry subject naming)
5. All fields have a `"default"` value (backward compatibility requirement)
6. `./mvnw generate-sources -pl common-events` succeeds (Java class generation)

**Feedback example:**
```
Avro schema issues in common-events/src/main/avro/order/PaymentCompletedEvent.avsc:
- fields missing 'default' (breaks BACKWARD compatibility): amount, currency
  Add a default value to every field.
```

---

### `warn-generated-files.sh` — PreToolUse · Write|Edit

**Purpose:** Blocks Claude from overwriting generated files before the write happens.
Moved to PreToolUse so the damage is prevented, not warned about after the fact.

**Detection:**
- Path contains `target/generated-sources` or `target/generated-test-sources`
- File contains `@Generated`, `@javax.annotation.Generated`, or `@jakarta.annotation.Generated`

**Redirect guidance:**
| Generated file | Edit this instead |
|---|---|
| Avro Java classes | `.avsc` in `common-events/src/main/avro/` |
| Lombok-generated methods | Annotation on the source class |
| MapStruct mappers | Mapper interface |

---

### `verify-gate.sh` — Stop

**Purpose:** The most powerful hook. Runs `./mvnw clean verify` on all modules touched
in the current turn before Claude is allowed to stop. If the build is red, exit 2 forces
Claude to continue and fix rather than stopping with a broken repo.

**Trigger condition:** Only fires if `.java` or `.sql` files appear in `git diff HEAD`.
Silent no-op for turns that only read files or run tests.

**Module detection:** `git diff --name-only HEAD | sed 's|/.*||' | sort -u`

**Feedback to Claude:**
```
Build is RED in: order-service. Fix all failures before stopping.
Run './mvnw clean verify -pl order-service -am' and address root causes —
do not suppress errors.
```

---

## `settings.json` structure

```
.claude/settings.json          ← committed; shared by the whole team
.claude/settings.local.json    ← gitignored; personal overrides only
```

Team hooks (all P1 + P2) go in `settings.json`.
Personal preferences (e.g. custom notification, extra audit destinations) go in `settings.local.json`.

---

## Adding a new hook

1. Create the script in `.claude/hooks/<name>.sh`
2. `chmod +x .claude/hooks/<name>.sh`
3. Add the entry to `.claude/settings.json` under the correct lifecycle event
4. Test locally: `echo '{"command":"your test input"}' | .claude/hooks/<name>.sh`
5. Add documentation to this file
6. Commit both the script and the updated `settings.json`

**Exit code reference:**

| Code | Meaning |
|---|---|
| `0` | Allow — Claude continues |
| `2` | Block — stderr shown to Claude; Claude must correct course |
| `stdout JSON {"additionalContext":"..."}` | Inject feedback without blocking |
| `stdout JSON {"sessionTitle":"..."}` | Set session title (SessionStart only) |

**Async hooks** (`"async": true`): run in the background; exit code ignored; no latency impact.
Use for logging/observability only — never for blocking.
