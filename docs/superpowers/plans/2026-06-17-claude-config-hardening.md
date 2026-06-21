# Claude Config Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every `.claude/` hook work correctly on Windows + Git Bash (no `python3`, single-module repo), fail closed on safety guards, and become verifiable via a test harness — raising every reviewed category to ≥9.5.

**Architecture:** Introduce a single sourced `_lib.sh` that all hooks use for JSON field extraction, fail-closed guard parsing, Maven module resolution, and JSON output emission. Refactor all 16 hooks onto it. Add a bash test harness with fixtures asserting exit codes. Move MCP config to the location Claude Code actually loads, tighten local permissions, and correct single-module assumptions in skills/agents.

**Tech Stack:** Bash (Git Bash on Windows), coreutils, `sed`, optional `python` (`C:\Program Files\Python314\python`), Maven wrapper `./mvnw`, Claude Code hooks (`settings.json`), MCP (`.mcp.json`).

## Global Constraints

- Target environment: Windows + Git Bash. `python3` is ABSENT; only `python` exists. `jq` is ABSENT. (verbatim from spec §1)
- Repo is currently single-module: root `pom.xml`, sources under `src/`. Module resolution must also handle a future nested-module monorepo. (spec §1, finding 2)
- Guard hooks (`block-dangerous`, `block-main-commit`, `secret-scan`, `protect-secrets`) MUST fail **closed** (`exit 2`) when input is present but unparseable. Advisory hooks MUST fail **open** (`exit 0`). (spec §3 D4, §5)
- Hook exit-code contract: `0` = allow, `2` = block (stderr shown to Claude), stdout JSON `{"additionalContext":"..."}` = inject feedback without blocking. (spec §4, hooks.md)
- No new hook *types*; no cross-platform abstraction. (spec §2 non-goals)
- Stage explicit paths only — never `git add -A`/`-all`. (CLAUDE.md Never list)
- Commit subject lines use Conventional Commits. Work happens on branch `docs/claude-config-hardening` (already created) or a `feat/` branch — never directly on `main`. (CLAUDE.md)
- Co-author footer on every commit: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task 1: `_lib.sh` foundation + test harness

**Files:**
- Create: `.claude/hooks/_lib.sh`
- Create: `.claude/hooks/test/run-tests.sh`

**Interfaces:**
- Produces (sourced by every later hook task):
  - `json_field <name>` → echoes top-level JSON string field from `$INPUT` (advisory use). Empty if absent/unparseable.
  - `guard_field <name>` → echoes field value; if the `"name"` key is present in raw `$INPUT` but extraction yields empty, prints a fail-closed message to stderr and `exit 2`.
  - `resolve_module <file_path>` → echoes `.` for the root module, a nested segment dir when `<seg>/pom.xml` exists, or empty when no pom is found.
  - `emit_context <message>` → prints `{"additionalContext":"<escaped message>"}` to stdout.
  - `guard_block <message>` → prints message to stderr, `exit 2`.
- Consumes: caller must set `INPUT=$(cat)` before calling any `*_field`/`emit_context`.

- [ ] **Step 1: Write the failing test harness**

Create `.claude/hooks/test/run-tests.sh`:

```bash
#!/usr/bin/env bash
# Test harness for .claude/hooks. Pipes JSON fixtures into hooks and asserts exit codes.
set -u
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

# assert_exit <desc> <expected_code> <hook-file> <json-input>
assert_exit() {
  local desc="$1" exp="$2" hook="$3" json="$4" code
  printf '%s' "$json" | "$HOOKS_DIR/$hook" >/tmp/hook_out 2>/tmp/hook_err
  code=$?
  if [ "$code" = "$exp" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $desc — exit $code, expected $exp"
    echo "  stderr: $(head -c 200 /tmp/hook_err)"
  fi
}

# assert_lib <desc> <expected> <command...>  (sources _lib.sh, runs a snippet)
assert_lib() {
  local desc="$1" exp="$2"; shift 2
  local got
  got="$("$@")"
  if [ "$got" = "$exp" ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); echo "FAIL: $desc — got '$got', expected '$exp'"; fi
}

# --- _lib.sh unit checks ---
lib_json() { INPUT="$1"; . "$HOOKS_DIR/_lib.sh"; json_field "$2"; }

assert_lib "json_field command simple"   "git status"            lib_json '{"command":"git status"}' command
assert_lib "json_field file_path"        "src/Main.java"         lib_json '{"file_path":"src/Main.java"}' file_path
assert_lib "json_field windows path"     'D:\IdeaProjects\x.java' lib_json '{"file_path":"D:\\IdeaProjects\\x.java"}' file_path
assert_lib "json_field absent -> empty"  ""                      lib_json '{"command":"x"}' file_path

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
```

```bash
chmod +x .claude/hooks/test/run-tests.sh
```

- [ ] **Step 2: Run the harness to verify it fails**

Run: `.claude/hooks/test/run-tests.sh`
Expected: FAIL — `_lib.sh` does not exist yet, so `json_field` is undefined (`PASS=0 FAIL=4`, non-zero exit).

- [ ] **Step 3: Write `_lib.sh`**

Create `.claude/hooks/_lib.sh`:

```bash
#!/usr/bin/env bash
# Shared helpers for .claude/hooks. SOURCE this file; do not execute it.
# Caller must set:  INPUT=$(cat)  before using *_field / emit_context.

# Resolve a python interpreter once (correctness fallback for parsing/emit).
_PY="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"

# json_field <name> — echo a top-level JSON string field from $INPUT.
# python-first (correct with escaped quotes), sed fallback when no python.
json_field() {
  local name="$1"
  if [ -n "$_PY" ]; then
    printf '%s' "${INPUT:-}" | "$_PY" -c '
import sys, json
name = sys.argv[1]
try:
    print(json.load(sys.stdin).get(name, ""))
except Exception:
    pass
' "$name" 2>/dev/null
    return
  fi
  # No python: best-effort sed for simple (unescaped) values.
  printf '%s' "${INPUT:-}" \
    | sed -n "s/.*\"$name\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
    | head -n1
}

# json_field_multiline <name> — for fields that may contain newlines (e.g. content).
json_field_multiline() {
  local name="$1"
  [ -n "$_PY" ] || return 0
  printf '%s' "${INPUT:-}" | "$_PY" -c '
import sys, json
name = sys.argv[1]
try:
    d = json.load(sys.stdin)
    print(d.get(name) or d.get("new_content") or d.get("content") or "")
except Exception:
    pass
' "$name" 2>/dev/null
}

# guard_field <name> — like json_field, but FAIL CLOSED:
# if the "name" key is present in raw $INPUT yet extraction is empty, block.
guard_field() {
  local name="$1" val
  val="$(json_field "$name")"
  if [ -z "$val" ] && printf '%s' "${INPUT:-}" | grep -q "\"$name\""; then
    echo "Blocked: safety hook could not parse '$name' from tool input (fail-closed)." >&2
    exit 2
  fi
  printf '%s' "$val"
}

# guard_block <message> — print to stderr and block.
guard_block() { echo "$1" >&2; exit 2; }

# resolve_module <file_path> — echo Maven module dir for the file:
#   nested "<seg>" when "<seg>/pom.xml" exists, else "." for the root pom, else empty.
resolve_module() {
  local file="$1" root seg
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  seg="${file%%/*}"
  if [ -n "$seg" ] && [ "$seg" != "$file" ] && [ -f "$root/$seg/pom.xml" ]; then
    printf '%s' "$seg"; return 0
  fi
  [ -f "$root/pom.xml" ] && printf '.'
}

# emit_context <message> — print {"additionalContext": "..."} to stdout (no block).
emit_context() {
  local msg="$1"
  if [ -n "$_PY" ]; then
    MSG="$msg" "$_PY" -c 'import os,json;print(json.dumps({"additionalContext":os.environ["MSG"]}))'
  else
    msg="${msg//\\/\\\\}"; msg="${msg//\"/\\\"}"; msg="${msg//$'\n'/\\n}"
    printf '{"additionalContext":"%s"}\n' "$msg"
  fi
}
```

- [ ] **Step 4: Run the harness to verify it passes**

Run: `.claude/hooks/test/run-tests.sh`
Expected: PASS — `PASS=4 FAIL=0`, exit 0. (On this machine `python` is used; the windows-path case confirms escaped backslashes survive.)

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/_lib.sh .claude/hooks/test/run-tests.sh
git commit -m "feat: add _lib.sh shared hook helpers and test harness

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Refactor guard hooks (fail-closed) + harden patterns

**Files:**
- Modify: `.claude/hooks/block-dangerous.sh`
- Modify: `.claude/hooks/block-main-commit.sh`
- Modify: `.claude/hooks/secret-scan.sh`
- Modify: `.claude/hooks/protect-secrets.sh`
- Modify: `.claude/hooks/test/run-tests.sh` (add fixtures)

**Interfaces:**
- Consumes: `json_field`, `guard_field`, `guard_block` from Task 1.

- [ ] **Step 1: Add failing guard fixtures to the harness**

Append before the `echo "----"` line in `.claude/hooks/test/run-tests.sh`:

```bash
# --- guard hooks (must fail CLOSED / block) ---
assert_exit "block rm -rf"            2 block-dangerous.sh '{"command":"rm -rf /tmp/x"}'
assert_exit "block rm -fr"            2 block-dangerous.sh '{"command":"rm -fr build"}'
assert_exit "block git add -A"        2 block-dangerous.sh '{"command":"git add -A"}'
assert_exit "block DROP TABLE"        2 block-dangerous.sh '{"command":"psql -c \"DROP TABLE orders\""}'
assert_exit "block DELETE no where"   2 block-dangerous.sh '{"command":"psql -c \"DELETE FROM orders;\""}'
assert_exit "block DELETE quoted tbl" 2 block-dangerous.sh '{"command":"psql -c \"DELETE FROM \\\"orders\\\"\""}'
assert_exit "allow safe ls"           0 block-dangerous.sh '{"command":"ls -la"}'
assert_exit "allow rm single file"    0 block-dangerous.sh '{"command":"rm target/app.jar"}'

assert_exit "secret-scan ignores non-commit" 0 secret-scan.sh '{"command":"ls"}'

assert_exit "protect-secrets blocks .env"  2 protect-secrets.sh '{"file_path":"<service-name>/.env"}'
assert_exit "protect-secrets blocks .pem"  2 protect-secrets.sh '{"file_path":"certs/server.pem"}'
assert_exit "protect-secrets allows .java" 0 protect-secrets.sh '{"file_path":"src/Main.java"}'
```

- [ ] **Step 2: Run harness — confirm guard fixtures fail**

Run: `.claude/hooks/test/run-tests.sh`
Expected: FAIL — current hooks call `python3` (absent) → empty command → `exit 0` (fail open). The "block …" fixtures return 0 instead of 2.

- [ ] **Step 3: Refactor `block-dangerous.sh`**

Replace the file body with:

```bash
#!/usr/bin/env bash
# PreToolUse — Bash. Blocks destructive shell commands. Fail-closed.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

CMD="$(guard_field command)"
[ -z "$CMD" ] && exit 0   # not a Bash call / no command -> nothing to guard

# rm -rf / rm -fr (both flag orderings)
echo "$CMD" | grep -qE '(^|\s|/)rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive.*--force|--force.*--recursive)' && \
  guard_block "Blocked: 'rm -rf' / 'rm -fr' is not permitted. Use explicit paths or 'git clean -fd'."

# Force-push to protected branches
echo "$CMD" | grep -qE 'git\s+push.*--(force|force-with-lease)' && \
  echo "$CMD" | grep -qE '(origin\s+(main|develop|master)|origin/(main|develop|master))' && \
  guard_block "Blocked: force-push to main/develop/master is not permitted."

# git add -A / --all
echo "$CMD" | grep -qE 'git\s+add\s+(-A|--all)\b' && \
  guard_block "Blocked: 'git add -A' is not permitted — stage explicit file paths."

# Destructive SQL (must live in Flyway migrations)
echo "$CMD" | grep -qiE '(DROP\s+TABLE|DROP\s+DATABASE|DROP\s+SCHEMA|TRUNCATE\s+TABLE)' && \
  guard_block "Blocked: destructive SQL (DROP/TRUNCATE) must live in a Flyway migration."

# DELETE without WHERE — handle optional schema-qualifier, quotes, optional ';'
echo "$CMD" | grep -qiE 'DELETE\s+FROM\s+("?[a-zA-Z_][a-zA-Z0-9_]*"?\.)?"?[a-zA-Z_][a-zA-Z0-9_]*"?\s*("|;|\\)?\s*$' && \
  ! echo "$CMD" | grep -qiE 'DELETE\s+FROM\s+.*\sWHERE\s' && \
  guard_block "Blocked: DELETE without WHERE detected — add a WHERE clause or soft-delete (deleted_at = now())."

# Bulk Docker teardown
echo "$CMD" | grep -qE 'docker\s+(rm|stop|kill)\s+\$\(docker\s+(ps|container)' && \
  guard_block "Blocked: bulk Docker container removal/stop is not permitted in agentic sessions."

exit 0
```

- [ ] **Step 4: Refactor `block-main-commit.sh`**

Replace the file body with:

```bash
#!/usr/bin/env bash
# PreToolUse — Bash. Blocks git commit on main/develop/master.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

CMD="$(guard_field command)"
echo "$CMD" | grep -qE 'git\s+commit' || exit 0

BRANCH=$(git branch --show-current 2>/dev/null)
case "$BRANCH" in
  main|develop|master)
    guard_block "Blocked: direct commits to '$BRANCH' are not permitted. Create a feature branch: git checkout -b <type>/<scope>-<desc>"
    ;;
esac
exit 0
```

- [ ] **Step 5: Refactor `protect-secrets.sh`**

Replace the `INPUT=$(cat)` + extraction preamble so it sources `_lib.sh` and uses `guard_field`; keep the existing `PATTERNS` array and loop:

```bash
#!/usr/bin/env bash
# PreToolUse — Read|Write|Edit|Bash. Blocks tool access to secrets files. Fail-closed.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

FILE_PATH="$(guard_field file_path)"
CMD="$(guard_field command)"
TARGET="${FILE_PATH} ${CMD}"

PATTERNS=(
  '\.env(\.|$)' '\.pem(\s|$)' '\.key(\s|$)' '\.p12(\s|$)' '\.pfx(\s|$)' '\.jks(\s|$)'
  '[^a-z]secrets?\.' '[^a-z]credentials?[^a-z]' 'id_rsa' 'id_ed25519' 'id_ecdsa'
  'application-prod(uction)?\.ya?ml'
)
for p in "${PATTERNS[@]}"; do
  echo "$TARGET" | grep -qiE "$p" && \
    guard_block "Blocked: access to a secrets/credentials file is not permitted (matched: $p). Use env vars or a secrets manager."
done
exit 0
```

- [ ] **Step 6: Refactor `secret-scan.sh`**

Replace only the preamble (source `_lib.sh`, use `guard_field`) and the python-emit block; keep the staged-diff scan logic but call it via `$_PY`:

```bash
#!/usr/bin/env bash
# PreToolUse — Bash (git commit). Scans staged content for secrets. Fail-closed on parse.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

CMD="$(guard_field command)"
echo "$CMD" | grep -qE 'git\s+commit' || exit 0
git rev-parse HEAD >/dev/null 2>&1 || exit 0
[ -z "$(git diff --staged 2>/dev/null)" ] && exit 0
[ -z "$_PY" ] && guard_block "Blocked: cannot scan staged diff for secrets (no python). Review manually or install python."

"$_PY" - << 'PYEOF'
import subprocess, sys, re
diff = subprocess.run(["git","diff","--staged"],capture_output=True,text=True).stdout
patterns = {
    "AWS Access Key": r'AKIA[0-9A-Z]{16}',
    "AWS Secret Key": r'(?i)aws.{0,20}secret.{0,20}["\']?[A-Za-z0-9/+=]{40}',
    "Private key header": r'-----BEGIN (RSA|EC|DSA|OPENSSH) PRIVATE KEY-----',
    "JWT token": r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',
    "Password in YAML": r'(?i)(password|passwd|secret|credentials?)\s*[:=]\s*["\']?(?!(\$\{|<|your|change|example|placeholder|test|dummy))[A-Za-z0-9!@#$%^&*]{8,}',
    "DB connection string": r'(?i)(jdbc:[a-z]+://[^"\';\s]*:[^"\';\s@]+@)',
    "Generic API key": r'(?i)(api[_-]?key|apikey|api[_-]?secret)\s*[:=]\s*["\']?[A-Za-z0-9_\-]{16,}',
    "Spring datasource password": r'(?i)spring\.datasource\.password\s*[:=]\s*(?!(\$\{|<))\S+',
}
hits=[]
for name,pat in patterns.items():
    for m in re.finditer(pat,diff):
        ln=diff[:m.start()].count("\n")+1
        hits.append(f"  [{name}] line ~{ln}: {m.group()[:60]}...")
if hits:
    sys.stderr.write("Blocked: potential secrets in staged changes:\n"+"\n".join(hits)+"\nRemove secrets before committing.\n")
    sys.exit(2)
PYEOF
exit $?
```

- [ ] **Step 7: Run the harness to verify all guard fixtures pass**

Run: `.claude/hooks/test/run-tests.sh`
Expected: PASS — all `block …` fixtures return 2, all `allow …` return 0.

Manual spot check:
Run: `echo '{"command":"rm -rf /"}' | .claude/hooks/block-dangerous.sh; echo "exit=$?"`
Expected: stderr block message, `exit=2`.

- [ ] **Step 8: Commit**

```bash
git add .claude/hooks/block-dangerous.sh .claude/hooks/block-main-commit.sh .claude/hooks/protect-secrets.sh .claude/hooks/secret-scan.sh .claude/hooks/test/run-tests.sh
git commit -m "fix: make guard hooks fail closed and parse input without python3

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Refactor path/advisory hooks

**Files:**
- Modify: `.claude/hooks/protect-migrations.sh`
- Modify: `.claude/hooks/warn-generated-files.sh`
- Modify: `.claude/hooks/dependency-check.sh`
- Modify: `.claude/hooks/audit-log.sh`
- Modify: `.claude/hooks/test/run-tests.sh` (add fixtures)

**Interfaces:**
- Consumes: `json_field`, `json_field_multiline`, `guard_block`, `emit_context`, `_PY`.

- [ ] **Step 1: Add failing fixtures**

Append before `echo "----"` in `run-tests.sh`:

```bash
# --- path / advisory hooks ---
assert_exit "protect-migrations allows new (untracked)" 0 protect-migrations.sh '{"file_path":"src/main/resources/db/migration/V99__new.sql"}'
assert_exit "warn-generated blocks generated-sources"   2 warn-generated-files.sh '{"file_path":"target/generated-sources/Foo.java"}'
assert_exit "warn-generated allows normal java"         0 warn-generated-files.sh '{"file_path":"src/main/java/Foo.java"}'
assert_exit "audit-log always allows"                   0 audit-log.sh '{"command":"ls"}'
```

- [ ] **Step 2: Run harness — confirm new fixtures fail**

Run: `.claude/hooks/test/run-tests.sh`
Expected: FAIL — `warn-generated-files` returns 0 (python3 absent → empty path → no match) instead of 2.

- [ ] **Step 3: Refactor `protect-migrations.sh`**

```bash
#!/usr/bin/env bash
# PreToolUse — Write|Edit. Blocks editing a committed Flyway migration.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

FILE="$(json_field file_path)"
echo "$FILE" | grep -qE 'db/migration/V[0-9]+__.*\.sql$' || exit 0
git ls-files --error-unmatch "$FILE" 2>/dev/null || exit 0
guard_block "Blocked: editing a committed Flyway migration is not permitted. Create V<n+1>__<description>.sql instead."
```

- [ ] **Step 4: Refactor `warn-generated-files.sh`**

```bash
#!/usr/bin/env bash
# PreToolUse — Write|Edit. Blocks overwriting generated files.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

FILE="$(json_field file_path)"
[ -z "$FILE" ] && exit 0

echo "$FILE" | grep -qE '(target/generated-sources|target/generated-test-sources)' && \
  guard_block "Blocked: '$FILE' is in target/generated-sources (auto-generated). Edit the source: .avsc for Avro, the @Lombok annotation, or the MapStruct mapper, then regenerate."

echo "$FILE" | grep -qE '\.java$' && [ -f "$FILE" ] && \
  grep -qE '@Generated|@javax\.annotation\.Generated|@jakarta\.annotation\.Generated' "$FILE" && \
  guard_block "Blocked: '$FILE' contains @Generated (auto-generated). Edit the source template/annotation instead."

exit 0
```

- [ ] **Step 5: Refactor `dependency-check.sh`**

```bash
#!/usr/bin/env bash
# PreToolUse — Write|Edit (pom.xml). Blocks inline <version> in non-root pom.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

FILE="$(json_field file_path)"
echo "$FILE" | grep -qE 'pom\.xml$' || exit 0

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ "$(realpath "$FILE" 2>/dev/null)" = "$(realpath "$ROOT/pom.xml" 2>/dev/null)" ] && exit 0

CONTENT="$(json_field_multiline new_content)"
[ -z "$CONTENT" ] && [ -f "$FILE" ] && CONTENT="$(cat "$FILE")"
[ -z "$CONTENT" ] && exit 0

# Detect <version> inside <dependency> blocks not using a ${property}.
printf '%s' "$CONTENT" | tr -d '\n' \
  | grep -oE '<dependency>.*?</dependency>' 2>/dev/null \
  | grep -E '<version>[^$<]' >/dev/null && \
  guard_block "Blocked: service pom.xml must not declare dependency versions inline. Manage versions in the root pom.xml BOM."

exit 0
```

- [ ] **Step 6: Refactor `audit-log.sh`**

```bash
#!/usr/bin/env bash
# PreToolUse — Bash (async). Appends every shell command to .claude/audit.log.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

CMD="$(json_field command)"
SESSION=${CLAUDE_SESSION_ID:-unknown}
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
LOG_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo '.')/.claude"
mkdir -p "$LOG_DIR"
printf '%s\t%s\t%s\t%s\n' "$TIMESTAMP" "$SESSION" "$BRANCH" "$CMD" >> "$LOG_DIR/audit.log"
exit 0
```

- [ ] **Step 7: Run harness — verify pass**

Run: `.claude/hooks/test/run-tests.sh`
Expected: PASS — all fixtures green.

- [ ] **Step 8: Commit**

```bash
git add .claude/hooks/protect-migrations.sh .claude/hooks/warn-generated-files.sh .claude/hooks/dependency-check.sh .claude/hooks/audit-log.sh .claude/hooks/test/run-tests.sh
git commit -m "fix: refactor path/advisory hooks onto _lib.sh

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Refactor SessionStart / Stop context hooks

**Files:**
- Modify: `.claude/hooks/inject-git-context.sh`
- Modify: `.claude/hooks/session-checkpoint.sh`

**Interfaces:**
- Consumes: `_PY`, `emit_context` from Task 1.
- Note: these hooks do not consume tool input fields; they emit JSON output and must not depend on a hardcoded `python3`.

- [ ] **Step 1: Refactor `inject-git-context.sh` output emission**

Keep the git-gathering block. Replace the trailing `python3 - << PYEOF ... PYEOF` JSON emission with `$_PY`, plus a no-python fallback:

```bash
# (after gathering BRANCH, LAST_TAG, UNCOMMITTED, UNTRACKED, MODULES, ISSUE_REF, RECENT)
. "$(dirname "$0")/_lib.sh"

CONTEXT="## Session context (auto-injected)
- **Branch**: $BRANCH
- **Last tag**: $LAST_TAG
- **Uncommitted files**: $UNCOMMITTED  |  **Untracked**: $UNTRACKED
- **Active modules**: ${MODULES:-（single-module: root pom）}
- **Issue**: ${ISSUE_REF:-none detected}

### Recent commits
\`\`\`
$RECENT
\`\`\`
"
if [ -n "$_PY" ]; then
  TITLE="$BRANCH" CTX="$CONTEXT" "$_PY" -c 'import os,json;print(json.dumps({"sessionTitle":os.environ["TITLE"],"additionalContext":os.environ["CTX"]}))'
else
  emit_context "$CONTEXT"
fi
exit 0
```

- [ ] **Step 2: Refactor `session-checkpoint.sh` interpreter use**

It already resolves `PYTHON_CMD`. Source `_lib.sh` and replace its local resolution with `_PY` for consistency; guard the MEMORY.md sync so it is skipped (not errored) when `_PY` is empty:

```bash
# near the MEMORY.md sync block:
. "$(dirname "$0")/_lib.sh"
if [ -f "$MEMORY_FILE" ] && [ -n "$_PY" ]; then
  "$_PY" -c "...existing sync script..." "$MEMORY_FILE" "$BRANCH" "$UNCOMMITTED" 2>/dev/null \
    && echo "MEMORY.md ## Active work section updated" >&2 \
    || echo "MEMORY.md update skipped (error)" >&2
fi
```

- [ ] **Step 3: Verify both run without error**

Run: `echo '{}' | .claude/hooks/inject-git-context.sh; echo "exit=$?"`
Expected: a single JSON object on stdout containing `sessionTitle` and `additionalContext`; `exit=0`.

Run: `echo '{}' | .claude/hooks/session-checkpoint.sh; echo "exit=$?"`
Expected: `.claude/session-checkpoint.md` rewritten; `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add .claude/hooks/inject-git-context.sh .claude/hooks/session-checkpoint.sh
git commit -m "fix: emit session-context JSON without hardcoded python3

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Maven hooks — module resolution + single-module + bulk gating

**Files:**
- Modify: `.claude/hooks/checkstyle-on-save.sh`
- Modify: `.claude/hooks/flyway-validate.sh`
- Modify: `.claude/hooks/verify-gate.sh`
- Modify: `.claude/hooks/avro-validate.sh`
- Modify: `.claude/hooks/n-plus-one-check.sh`
- Modify: `.claude/hooks/api-contract-check.sh`
- Modify: `.claude/hooks/test/run-tests.sh` (add fixtures)

**Interfaces:**
- Consumes: `json_field`, `resolve_module`, `emit_context`, `_PY`.
- `resolve_module` returns `.` for the root module → build commands omit `-pl`.

- [ ] **Step 1: Add failing fixtures**

Append before `echo "----"` in `run-tests.sh`:

```bash
# --- maven / advisory hooks resolve module and never block ---
assert_exit "checkstyle non-java no-op"  0 checkstyle-on-save.sh '{"file_path":"README.md"}'
assert_exit "flyway non-sql no-op"       0 flyway-validate.sh '{"file_path":"src/main/java/Foo.java"}'
assert_exit "n+1 non-java no-op"         0 n-plus-one-check.sh '{"file_path":"pom.xml"}'
assert_exit "api-contract non-java no-op" 0 api-contract-check.sh '{"file_path":"pom.xml"}'
assert_exit "avro non-avsc no-op"        0 avro-validate.sh '{"file_path":"Foo.java"}'

# resolve_module unit: a single-module repo file resolves to "."
lib_mod() { INPUT='{}'; . "$HOOKS_DIR/_lib.sh"; resolve_module "$1"; }
assert_lib "resolve_module root file -> ." "." lib_mod "src/main/java/Foo.java"
```

- [ ] **Step 2: Run harness — confirm resolve_module fixture fails**

Run: `.claude/hooks/test/run-tests.sh`
Expected: FAIL — `resolve_module root file -> .` not yet exercised by hooks; the no-op fixtures may already pass but the build path is wrong. (If `src/pom.xml` does not exist, current hooks no-op silently — the bug this task fixes.)

- [ ] **Step 3: Refactor `checkstyle-on-save.sh`**

```bash
#!/usr/bin/env bash
# PostToolUse — Write|Edit (.java). Runs Checkstyle; injects violations as context.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

FILE="$(json_field file_path)"
echo "$FILE" | grep -qE '\.java$' || exit 0
[ -f "$FILE" ] || exit 0
[ "${CLAUDE_HOOK_SKIP_CHECKSTYLE:-0}" = "1" ] && exit 0

MODULE="$(resolve_module "$FILE")"
[ -z "$MODULE" ] && exit 0
if [ "$MODULE" = "." ]; then PL=(); else PL=(-pl "$MODULE"); fi

OUTPUT=$(./mvnw checkstyle:check "${PL[@]}" -q 2>&1)
[ $? -eq 0 ] && exit 0
VIOLATIONS=$(echo "$OUTPUT" | grep -E '\[WARN\]|\[ERROR\]' | head -20)
emit_context "Checkstyle violations in $FILE:
$VIOLATIONS
Fix before proceeding."
exit 0
```

- [ ] **Step 4: Refactor `flyway-validate.sh`**

```bash
#!/usr/bin/env bash
# PostToolUse — Write (db/migration/*.sql). Runs flyway:validate.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

FILE="$(json_field file_path)"
echo "$FILE" | grep -qE 'db/migration/.*\.sql$' || exit 0

MODULE="$(resolve_module "$FILE")"
[ -z "$MODULE" ] && exit 0
if [ "$MODULE" = "." ]; then PL=(); else PL=(-pl "$MODULE"); fi

OUTPUT=$(./mvnw flyway:validate "${PL[@]}" -q 2>&1)
[ $? -eq 0 ] && exit 0
REASON=$(echo "$OUTPUT" | grep -E 'ERROR|WARN|FlywayException|Validate' | head -10)
emit_context "Flyway validation failed after writing $FILE:
$REASON
Check version, filename format (V<n>__<desc>.sql), and checksum."
exit 0
```

- [ ] **Step 5: Refactor `verify-gate.sh`**

Keep the `RELEVANT` early-exit and module derivation, but build per-module via `resolve_module` semantics (root `.` omits `-pl`) and emit via `emit_context`:

```bash
#!/usr/bin/env bash
# Stop hook. Runs ./mvnw verify on modules with changed .java/.sql. Fail = exit 2.
. "$(dirname "$0")/_lib.sh"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); [ -z "$REPO_ROOT" ] && exit 0

CHANGED=$( { git diff --name-only; git diff --cached --name-only; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u )
RELEVANT=$(echo "$CHANGED" | grep -E '\.(java|sql)$')
[ -z "$RELEVANT" ] && exit 0

# Derive modules: for each changed file, resolve_module; unique.
MODULES=$(for f in $RELEVANT; do resolve_module "$f"; echo; done | sort -u | grep -v '^$')

FAILED=()
for MODULE in $MODULES; do
  if [ "$MODULE" = "." ]; then PL=(); else PL=(-pl "$MODULE" -am); fi
  OUTPUT=$(cd "$REPO_ROOT" && ./mvnw verify "${PL[@]}" -q 2>&1)
  if [ $? -ne 0 ]; then
    OUTPUT=$(cd "$REPO_ROOT" && ./mvnw clean verify "${PL[@]}" -q 2>&1)
  fi
  if [ $? -ne 0 ]; then
    FAILED+=("$MODULE")
    echo "BUILD FAILURE in: $MODULE" >&2
    echo "$OUTPUT" | grep -E 'ERROR|FAILED|Tests run:.*Failures|BUILD' | head -15 >&2
  fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
  emit_context "Build is RED in: ${FAILED[*]}. Fix all failures before stopping. Run './mvnw verify' and address root causes — do not suppress errors or skip tests."
  exit 2
fi
exit 0
```

- [ ] **Step 6: Refactor `avro-validate.sh`, `n-plus-one-check.sh`, `api-contract-check.sh`**

For each: replace the `INPUT`/`python3` preamble with `. "$(dirname "$0")/_lib.sh"` + `FILE="$(json_field file_path)"`, and replace the `python3 -c "...json.dumps..."` emit calls with `emit_context "<message>"`. The Python *analysis* blocks (`avro-validate` schema check, `n-plus-one` regex scan, `api-contract` path scan) run via `$_PY` and must guard `[ -z "$_PY" ] && exit 0` (advisory → fail open). `avro-validate` also uses `resolve_module` for the `generate-sources` `-pl` flag (root → omit).

Concrete preamble for each (example `n-plus-one-check.sh`):

```bash
#!/usr/bin/env bash
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"
FILE="$(json_field file_path)"
echo "$FILE" | grep -qE '\.java$' || exit 0
[ -f "$FILE" ] || exit 0
[ -z "$_PY" ] && exit 0
WARN="$("$_PY" - "$FILE" << 'PYEOF'
# ... existing regex scan, but print plain text (one warning per line), no json ...
PYEOF
)"
[ -n "$WARN" ] && emit_context "N+1 / performance warnings in $FILE:
$WARN"
exit 0
```

(Apply the analogous preamble to `avro-validate.sh` and `api-contract-check.sh`, keeping their existing analysis logic but printing plain text and wrapping output with `emit_context`.)

- [ ] **Step 7: Run harness — verify pass**

Run: `.claude/hooks/test/run-tests.sh`
Expected: PASS — including `resolve_module root file -> .`.

Manual check (single-module build path):
Run: `printf '{"file_path":"src/main/java/com/ganchevdimitarg/claudetemplate/ClaudeTemplateApplication.java"}' | .claude/hooks/checkstyle-on-save.sh; echo "exit=$?"`
Expected: runs `./mvnw checkstyle:check` (no `-pl`); `exit=0` (or context with violations); no silent skip.

- [ ] **Step 8: Commit**

```bash
git add .claude/hooks/checkstyle-on-save.sh .claude/hooks/flyway-validate.sh .claude/hooks/verify-gate.sh .claude/hooks/avro-validate.sh .claude/hooks/n-plus-one-check.sh .claude/hooks/api-contract-check.sh .claude/hooks/test/run-tests.sh
git commit -m "fix: Maven hooks resolve single-module repo and emit via _lib.sh

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: MCP — root `.mcp.json` + slim reference

**Files:**
- Create: `.mcp.json` (repo root)
- Modify: `.claude/mcp.json` (slim to a documented reference)

**Interfaces:** none (config files).

- [ ] **Step 1: Create root `.mcp.json`**

```json
{
  "mcpServers": {
    "context7": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    },
    "github": {
      "type": "url",
      "url": "https://api.githubcopilot.com/mcp/"
    }
  }
}
```

- [ ] **Step 2: Slim `.claude/mcp.json` to a reference**

Replace its contents with a documentation-only catalogue (no `mcpServers` key that implies auto-load):

```json
{
  "_note": "Reference catalogue only. Active servers are configured in the repo-root .mcp.json (loaded by Claude Code) or via `claude mcp add`. Servers below are documented for when their backing service is deployed.",
  "available": {
    "context7":        { "active": true,  "where": "root .mcp.json", "purpose": "Live library docs (Spring Boot, Avro, Kafka, Testcontainers, Resilience4j)." },
    "github":          { "active": true,  "where": "root .mcp.json", "purpose": "Read PRs, issues, CI status. Requires GITHUB_TOKEN (repo scope)." },
    "postgres":        { "active": false, "purpose": "Inspect live schema before migrations. Set POSTGRES_MCP_URL; add to root .mcp.json when needed." },
    "schema-registry": { "active": false, "purpose": "Query Avro schemas / compatibility. Set SCHEMA_REGISTRY_MCP_URL." },
    "jira":            { "active": false, "purpose": "Read ticket descriptions / acceptance criteria. Set JIRA_MCP_URL + JIRA_TOKEN." }
  }
}
```

- [ ] **Step 3: Verify Claude Code lists the servers**

Run (manual, in Claude Code): `/mcp`
Expected: `context7` connected; `github` listed (connects when `GITHUB_TOKEN` is set).

- [ ] **Step 4: Commit**

```bash
git add .mcp.json .claude/mcp.json
git commit -m "fix: load MCP servers from root .mcp.json; slim .claude/mcp.json to reference

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Tighten permissions + add `.gitignore`

**Files:**
- Modify: `.claude/settings.local.json`
- Create: `.gitignore` (repo root)

**Interfaces:** none.

- [ ] **Step 1: Rewrite `.claude/settings.local.json`**

```json
{
  "permissions": {
    "allow": [
      "Bash(./mvnw *)",
      "Bash(git status)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git add -p)",
      "Bash(git restore *)",
      "Bash(.claude/hooks/test/run-tests.sh)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(rm -fr *)",
      "Bash(git add -A)",
      "Bash(git add --all)",
      "Bash(git push --force *)",
      "Bash(git push --force-with-lease *)"
    ]
  }
}
```

- [ ] **Step 2: Create `.gitignore`**

```gitignore
# Claude Code — local only; never commit
.claude/audit.log
.claude/settings.local.json
.claude/session-checkpoint.md

# Windows / Git Bash crash dumps
sh.exe.stackdump
```

- [ ] **Step 3: Verify ignore + no broad allow remains**

Run: `git check-ignore .claude/audit.log .claude/settings.local.json .claude/session-checkpoint.md sh.exe.stackdump`
Expected: all four paths echoed (ignored).

Run: `grep -c 'bash \*' .claude/settings.local.json`
Expected: `0`.

- [ ] **Step 4: Commit**

```bash
git add .gitignore .claude/settings.local.json
git commit -m "fix: tighten settings.local.json permissions and add .gitignore

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Correct single-module assumptions in skills & agents

**Files:**
- Modify: `.claude/skills/write/SKILL.md`
- Modify: `.claude/skills/test/SKILL.md`
- Modify: `.claude/skills/migrate/SKILL.md`
- Modify: `.claude/skills/review/SKILL.md`
- Modify: `.claude/skills/commit/SKILL.md`
- Modify: `.claude/agents/code-writer.md`
- Modify: `.claude/agents/test-agent.md`
- Modify: `.claude/agents/git-agent.md`

**Interfaces:** none (instruction docs).

- [ ] **Step 1: Find every `-pl <module>` reference**

Run: `grep -rn 'pl <module>\|-pl \$\|clean verify -pl' .claude/skills .claude/agents`
Expected: a list of lines using `./mvnw ... -pl <module> -am`.

- [ ] **Step 2: Replace verify commands with single-module form**

For each match, change `./mvnw clean verify -pl <module> -am` → `./mvnw clean verify`, and add a one-line note where a verify command appears:

```markdown
- Verify: `./mvnw clean verify` (single-module repo; for a future monorepo add `-pl <module> -am`).
```

Apply the same to `flyway:validate`, `checkstyle:check`, and `generate-sources` invocations: drop `-pl <module>` for this repo, keep the monorepo note once per file.

- [ ] **Step 3: Verify no stale `-pl <module>` remains**

Run: `grep -rn '\-pl <module>' .claude/skills .claude/agents`
Expected: no output (all replaced or annotated).

- [ ] **Step 4: Commit**

```bash
git add .claude/skills .claude/agents
git commit -m "docs: correct skill/agent verify commands for single-module repo

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Update `hooks.md` documentation

**Files:**
- Modify: `.claude/hooks.md`

**Interfaces:** none.

- [ ] **Step 1: Add `_lib.sh` + contract sections**

Insert after the "exit code contract" intro:

```markdown
## Shared library: `_lib.sh`

All hooks `source .claude/hooks/_lib.sh` for:
- `json_field <name>` / `json_field_multiline <name>` — parse tool input without requiring `python3` (python-first, `sed` fallback).
- `guard_field <name>` — fail-CLOSED extraction for guard hooks: if the key is present in the raw input but parsing yields empty, the hook blocks (`exit 2`).
- `resolve_module <file>` — returns `.` for the single-module root pom, a nested module dir for a monorepo, or empty when no pom exists. Build commands omit `-pl` when the module is `.`.
- `emit_context <message>` / `guard_block <message>` — standard stdout-JSON / stderr-block emitters.

### Fail-closed vs fail-open
- **Guard hooks** (`block-dangerous`, `block-main-commit`, `secret-scan`, `protect-secrets`): block on unparseable input.
- **Advisory hooks** (everything else): no-op (`exit 0`) when they cannot run.

## Testing hooks

Run `.claude/hooks/test/run-tests.sh` — pipes JSON fixtures into each hook and asserts exit codes. Add a fixture for every new rule. CI wiring is a follow-up.
```

- [ ] **Step 2: Update the lifecycle list**

In the lifecycle diagram and the "Adding a new hook" steps, note that single-module repos run Maven without `-pl`, and that new hooks must source `_lib.sh` and add a `run-tests.sh` fixture.

- [ ] **Step 3: Verify the test command in docs works**

Run: `.claude/hooks/test/run-tests.sh; echo "exit=$?"`
Expected: `PASS=<n> FAIL=0`, `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add .claude/hooks.md
git commit -m "docs: document _lib.sh, fail-closed contract, and hook test harness

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] Run the full harness: `.claude/hooks/test/run-tests.sh` → `FAIL=0`.
- [ ] Manual guard checks (each prints a block message, `exit=2`):
  - `echo '{"command":"rm -rf /"}' | .claude/hooks/block-dangerous.sh`
  - `echo '{"command":"git commit -m x"}' | .claude/hooks/block-main-commit.sh` (on a protected branch)
  - `echo '{"file_path":"x/.env"}' | .claude/hooks/protect-secrets.sh`
- [ ] `/mcp` lists `context7` (+ `github` with token).
- [ ] `git check-ignore` reports the four local paths ignored.
- [ ] `grep -rn '\-pl <module>' .claude/skills .claude/agents` → no output.

---

## Self-review notes

- **Spec coverage:** every acceptance criterion in spec §7 maps to a task — runtime/fail-closed (T1–T5), hook design hardening (T2), settings wiring + bulk gating (T2,T5), MCP (T6), skills/agents (T8), permissions + gitignore (T7), docs (T9).
- **Type consistency:** helper names (`json_field`, `json_field_multiline`, `guard_field`, `guard_block`, `resolve_module`, `emit_context`, `_PY`) are defined once in Task 1 and used verbatim in Tasks 2–5.
- **Fail semantics:** guards use `guard_field`/`guard_block`; advisory hooks use `json_field` + `[ -z "$_PY" ] && exit 0`, matching spec §5.
