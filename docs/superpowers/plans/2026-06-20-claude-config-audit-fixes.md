# Claude Config Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four gaps from the 2026-06-20 setup audit — over-broad local permissions, three-way rule duplication, leftover allow-list cruft, and repo hygiene — without weakening any guardrail.

**Architecture:** Pure config + docs changes. No Java, no hooks logic changes. Each task is verified by the existing hook test harness (`.claude/hooks/test/run-tests.sh`), JSON validity, and `grep` assertions. Single source of truth for convention *rules* is `CLAUDE.md` (always loaded); skills/agents govern *process* and point at it.

**Tech Stack:** JSON (`settings.local.json`), Markdown (skills, agents, docs), Git Bash, Python (JSON validation only).

## Global Constraints

- Never weaken a guard: the `deny` list and all PreToolUse guard hooks stay intact — verbatim values preserved.
- `.claude/settings.local.json` is **gitignored** (`.gitignore:3`) — changes to it are local-only and CANNOT be committed. Durable/team-visible fixes go in a committed `.claude/settings.local.example.json`.
- British English in all prose (per `.claude/CLAUDE.md`).
- Conventional Commits; commit subject confirmed with the user before committing (per `.claude/CLAUDE.md § Session behaviour`).
- Never commit on `main`/`develop` — work on the current `docs/claude-config-hardening` branch (the `block-main-commit` hook enforces this).
- Hook harness must read `PASS=<n> FAIL=0` after any change touching `.claude/`.
- This is a single-module template repo: do NOT scaffold infrastructure for code that does not exist.

---

## File Structure

| File | Change | Responsibility after change |
|---|---|---|
| `.claude/settings.local.json` | Modify | Curated minimal personal allow-list (local-only) |
| `.claude/settings.local.example.json` | Create | Committed baseline showing the recommended safe permission set |
| `.claude/skills/write/SKILL.md` | Modify | Process only (order, verify loop); rules delegated to CLAUDE.md |
| `.claude/agents/code-writer.md` | Modify | Trim restated rules to a pointer; keep agent-specific framing |
| `.gitignore` | Modify | Ignore generated `HELP.md` |
| `docs/decisions.md` | Modify | Record the single-source-of-truth decision |
| `MEMORY.md` | Commit | Pending modification cleared |

---

## Task 1: Curate the local permission allow-list + committed baseline

Removes arbitrary-execution allows (`bash *`, `git *`, `git add *`, `python *`), debug echoes (`echo "EXIT:$?"`), and one-off bootstrap cruft (`ps_new.tmp`, `dbg.json`, brainstorming `cp`/`mkdir`/`sed`). Adds a committed example so template users inherit the safe baseline.

**Files:**
- Modify: `.claude/settings.local.json` (full rewrite of `permissions.allow`)
- Create: `.claude/settings.local.example.json`

**Interfaces:**
- Produces: a committed `settings.local.example.json` that other tasks/users copy to `settings.local.json`.

- [ ] **Step 1: Record current state as the failing assertion**

Run:
```bash
grep -nE '"Bash\((bash|git|python|git add) \*\)"' .claude/settings.local.json
```
Expected: matches on `Bash(bash *)`, `Bash(git *)`, `Bash(git add *)`, `Bash(python *)` — these are the over-broad allows to remove.

- [ ] **Step 2: Rewrite `.claude/settings.local.json` to the curated set**

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
      "Bash(git commit *)",
      "Bash(.claude/hooks/test/run-tests.sh)",
      "Bash(bash .claude/hooks/test/run-tests.sh)",
      "Bash(python -c \"import json;json.load\\(open\\('.claude/settings.json'\\)\\);json.load\\(open\\('.claude/mcp.json'\\)\\);json.load\\(open\\('.claude/settings.local.json'\\)\\);print\\('settings.json, mcp.json, settings.local.json: all valid JSON'\\)\")",
      "Read(//d//**)",
      "Read(//c/Users/Dimitar/**)",
      "Read(//tmp/**)",
      "Bash(/c/Users/Dimitar/AppData/Roaming/Python/Python314/Scripts/code-review-graph.exe --help)",
      "Bash(\"/c/Users/Dimitar/AppData/Roaming/Python/Python314/Scripts/code-review-graph.exe\" build *)",
      "Bash(\"/c/Users/Dimitar/AppData/Roaming/Python/Python314/Scripts/code-review-graph.exe\" status *)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(rm -fr *)",
      "Bash(git add -A)",
      "Bash(git add --all)",
      "Bash(git push --force *)",
      "Bash(git push --force-with-lease *)"
    ]
  },
  "enabledMcpjsonServers": [
    "context7",
    "github",
    "code-review-graph"
  ]
}
```
Rationale per removal: `Bash(bash *)`/`Bash(python *)` = arbitrary execution; `Bash(git *)`/`Bash(git add *)` = re-open the surface the `deny` list and `block-main-commit`/`block-dangerous` hooks narrow; `echo "EXIT:$?"`/`echo "exit=$?"`/`grep -nP "^\s*$"` = debug leftovers; `cp ...ps_new.tmp`, `rm ...dbg.json dbg2.sh`, `mkdir/cp -R/sed ...brainstorming` = one-off bootstrap that is done. The specific `code-review-graph.exe` and JSON-validate allows are kept (narrow, useful).

- [ ] **Step 3: Verify JSON validity**

Run:
```bash
python -c "import json;json.load(open('.claude/settings.local.json'));print('valid')"
```
Expected: `valid`

- [ ] **Step 4: Verify the broad allows are gone**

Run:
```bash
grep -nE '"Bash\((bash|git|python|git add) \*\)"' .claude/settings.local.json; echo "exit=$?"
```
Expected: no matches, `exit=1`.

- [ ] **Step 5: Create the committed baseline `.claude/settings.local.example.json`**

Same as Step 2 but with machine-specific absolute paths replaced by placeholders, and a header note. Write:
```json
{
  "_note": "Copy to settings.local.json (gitignored) and replace <...> placeholders. This is the recommended minimal safe baseline — narrow allows, never blanket 'Bash(bash *)' / 'Bash(git *)'. The deny list and PreToolUse guard hooks are your real safety net; keep this allow-list tight.",
  "permissions": {
    "allow": [
      "Bash(./mvnw *)",
      "Bash(git status)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git add -p)",
      "Bash(git restore *)",
      "Bash(git commit *)",
      "Bash(.claude/hooks/test/run-tests.sh)",
      "Bash(bash .claude/hooks/test/run-tests.sh)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(rm -fr *)",
      "Bash(git add -A)",
      "Bash(git add --all)",
      "Bash(git push --force *)",
      "Bash(git push --force-with-lease *)"
    ]
  },
  "enabledMcpjsonServers": [
    "context7",
    "github",
    "code-review-graph"
  ]
}
```

- [ ] **Step 6: Verify the example is valid JSON and tracked**

Run:
```bash
python -c "import json;json.load(open('.claude/settings.local.example.json'));print('valid')"
git check-ignore .claude/settings.local.example.json; echo "ignored_exit=$?"
```
Expected: `valid`; `ignored_exit=1` (NOT ignored — it must be committable).

- [ ] **Step 7: Confirm subject line, then commit the example only**

`settings.local.json` is gitignored and will not be staged; only the example is committed.
```bash
git add .claude/settings.local.example.json
git commit -m "chore(claude-config): add minimal-permission settings.local baseline"
```

---

## Task 2: Make CLAUDE.md the single source of convention rules

`write/SKILL.md` lines 27-76 restate Lombok/Flyway/Redis/Avro/Kafka/Validation/Pagination/Security rules that already live verbatim in `CLAUDE.md` and its `@import` files (always in context). Three copies drift. Trim the skill to the *process* and delegate rules. Keep `review/SKILL.md` untouched — its severity-tagged checklist is a distinct, valuable representation, not a duplicate.

**Files:**
- Modify: `.claude/skills/write/SKILL.md:27-76` (replace rule blocks with a pointer)
- Modify: `.claude/agents/code-writer.md` (already says "follow write/SKILL.md"; ensure its invariants read as emphasis, not a second rulebook)
- Modify: `docs/decisions.md` (record the decision)

**Interfaces:**
- Consumes: `CLAUDE.md` convention sections (Lombok, Flyway, Redis, Avro, Kafka, Validation, Pagination, Security) — unchanged, canonical.
- Produces: `write/SKILL.md` that contains the implementation *order* and *verify loop* but no restated rules.

- [ ] **Step 1: Capture the duplication as the failing assertion**

Run:
```bash
grep -cE '^## (Lombok|Flyway|Redis|Avro|Kafka|Validation|Pagination|Security) rules' .claude/skills/write/SKILL.md
```
Expected: `8` (eight duplicated rule sections present).

- [ ] **Step 2: Replace `write/SKILL.md` rule sections (lines 27-76) with a delegation pointer**

Delete everything from `## Lombok rules` (line 27) to the end of `## Security rules`, and replace with:
```markdown
## Convention rules — single source of truth

This skill governs the **process** (implementation order + the verify loop above).
The **rules** for Lombok, records, Flyway, Redis, Avro/Schema Registry, Kafka,
validation, pagination, and security live in `CLAUDE.md` and its `@import` files,
which are always in context. Do not restate them here — follow them as written
there. If a rule and this skill ever disagree, `CLAUDE.md` wins.
```
Keep `## Steps` (lines 1-25) exactly as-is — it is the unique, valuable part.

- [ ] **Step 3: Verify the rule blocks are gone but Steps remain**

Run:
```bash
grep -cE '^## (Lombok|Flyway|Redis|Avro|Kafka|Validation|Pagination|Security) rules' .claude/skills/write/SKILL.md; echo "rules_exit=$?"
grep -c '^## Steps' .claude/skills/write/SKILL.md
```
Expected: `0` rule sections (`rules_exit=1`); `1` Steps section.

- [ ] **Step 4: Trim `code-writer.md` restated invariants to a pointer**

In `.claude/agents/code-writer.md`, the "Key invariants you must never violate" block restates rules already in `write/SKILL.md`/`CLAUDE.md`. Replace the bulleted invariant list with:
```markdown
Key invariants (full rules in CLAUDE.md; process in write/SKILL.md):
- **Schema-first** — Flyway migration before any Java code.
- **Records-first** — records for immutable types; Lombok only when a record cannot be used.
- **Verify gate** — `./mvnw clean verify` green before stopping; on unresolvable failure, `git restore src/` and report. Never suppress errors.
- **Tests scope** — one happy-path unit + one happy-path integration test; full coverage is test-agent's job.
```
This keeps the agent-specific framing (cold start, tests-vs-test-agent boundary, output format) and drops the second rulebook.

- [ ] **Step 5: Record the decision**

Append to `docs/decisions.md`:
```markdown
- 2026-06-20 — Convention rules have a single source of truth: `CLAUDE.md` + its `@import` files. Skills and agents reference them and govern process only; they do not restate rules. `review/SKILL.md`'s severity checklist is the one allowed alternative representation (it adds Critical/Warning/Suggestion tagging). Rationale: kill three-way drift flagged in the 2026-06-20 setup audit.
```

- [ ] **Step 6: Run the hook harness (skills/agents are config the harness exercises indirectly)**

Run:
```bash
bash .claude/hooks/test/run-tests.sh 2>&1 | tail -2
```
Expected: `PASS=35 FAIL=0`.

- [ ] **Step 7: Confirm subject line, then commit**

```bash
git add .claude/skills/write/SKILL.md .claude/agents/code-writer.md docs/decisions.md
git commit -m "refactor(claude-config): single-source convention rules in CLAUDE.md"
```

---

## Task 3: Repo hygiene

Generated `HELP.md` is untracked clutter; `MEMORY.md` has an uncommitted modification. Resolve both.

**Files:**
- Modify: `.gitignore` (add `HELP.md`)
- Inspect + commit: `MEMORY.md`

- [ ] **Step 1: Confirm HELP.md is the Spring Boot generated file**

Run:
```bash
head -3 HELP.md
git status --short HELP.md
```
Expected: Spring Boot "Getting Started" generated content; `?? HELP.md` (untracked).

- [ ] **Step 2: Add HELP.md to `.gitignore`**

Append under the Build section of `.gitignore`:
```gitignore

# Spring Boot generated help (regenerated by the initializr)
HELP.md
```

- [ ] **Step 3: Verify it is now ignored**

Run:
```bash
git check-ignore HELP.md; echo "exit=$?"
```
Expected: `HELP.md`, `exit=0`.

- [ ] **Step 4: Review the MEMORY.md change and commit hygiene fixes**

Run `git diff MEMORY.md` and confirm the change is a legitimate memory update (not stray content). Then:
```bash
git add .gitignore MEMORY.md
git commit -m "chore: ignore generated HELP.md; sync MEMORY.md"
```
Expected: clean `git status` for these paths afterwards.

---

## Suggestions (not tasked — judgement calls for the user)

These came out of the audit but are intentional trade-offs for a *template*, so they are recommendations rather than fixes:

1. **Aspirational config mass is acceptable as-is.** The advisory hooks (avro/flyway/n+1/api-contract) and the Kafka/Mongo/Avro CLAUDE.md sections target code that does not exist yet, but they no-op cleanly and the repo-maturity preamble names them. For a template this is the product. Only trim if the repo commits to staying single-module long-term. *No action recommended.*

2. **Optional: a `make`/script to scaffold `settings.local.json` from the example.** Add a one-liner to `SETUP.md`: `cp .claude/settings.local.example.json .claude/settings.local.json` then edit placeholder paths. Low effort, helps template users start safe.

3. **Optional: periodic allow-list audit.** Add a note to `hooks.md` reminding that `settings.local.json` accumulates one-off allows over time and should be re-curated against the `.example` baseline occasionally.

4. **Optional: a hook-harness fixture for the permission baseline.** If you want the curated allow-list to be regression-protected, add a fixture that greps `settings.local.example.json` for forbidden patterns (`Bash(bash *)`, `Bash(git *)`). Only worth it if drift recurs.

---

## Self-Review

- **Coverage:** Audit gap 1 (broad permissions) → Task 1. Gap 2 (rule duplication) → Task 2. Gap 3 (allow-list cruft) → folded into Task 1. Gap 4 (config mass) → Suggestions (intentional). File hygiene → Task 3. All covered.
- **Placeholder scan:** No TBD/TODO; every config/code step shows exact content and exact verify command with expected output.
- **Consistency:** `settings.local.example.json` produced in Task 1 is referenced consistently in Task 3 Suggestions and SETUP note. `CLAUDE.md` named as canonical in both Task 2 and `docs/decisions.md`.
- **Constraint check:** Task 1 commits only the `.example` (real local file stays gitignored — Step 6/7 enforce this); no task commits on `main`; deny list preserved verbatim.
