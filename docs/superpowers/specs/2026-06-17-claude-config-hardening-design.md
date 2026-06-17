# Claude Code Setup Hardening — Design Spec

**Date:** 2026-06-17
**Status:** Approved for planning
**Scope:** Personal Claude Code config for the `claude-template` repo, running on Windows + Git Bash.
**Goal:** Raise every evaluated category of the `.claude/` setup to a score of ≥9.5.

---

## 1. Background

A scored review of `.claude/` found the *design* of the setup to be strong (~9/10 on
Linux/macOS) but the *deployed* setup defective on the actual environment (Windows + Git Bash):

| Category | Current score |
|---|---|
| Hook design & coverage | 9 |
| **Hook runtime (this machine)** | **3** |
| settings.json wiring | 8 |
| MCP config (effective) | 4 |
| Skills | 9 |
| Agents | 9 |
| Permissions hygiene | 5 |
| Documentation | 10 |

### Root-cause findings

1. **`python3` is missing on this machine** (only `python` exists, at
   `C:\Program Files\Python314\` — a path containing a space). Every hook except
   `session-checkpoint.sh` extracts its JSON input via `... | python3 -c "..." 2>/dev/null`.
   With `python3` absent the command fails, `2>/dev/null` swallows it, the field is empty,
   and the guard `grep -qE ... || exit 0` treats empty input as "no match" → **`exit 0` →
   action permitted**. All guard hooks (`block-dangerous`, `block-main-commit`,
   `secret-scan`, `protect-secrets`) and all advisory hooks **silently fail open**.

2. **Module detection assumes a multi-module monorepo.** Hooks derive the Maven module with
   `MODULE=$(echo "$FILE" | cut -d'/' -f1)` and run `./mvnw ... -pl <module>`. But
   `docs/context/project-layout.md` states this repo is a **single module** with sources at
   `src/main/java/...`. So `cut -d'/' -f1` yields `src`, `[ -f src/pom.xml ]` fails, and
   `checkstyle-on-save`, `flyway-validate`, and `verify-gate` **silently no-op** on this repo.

3. **MCP config is in a non-loaded location.** Claude Code loads project MCP servers from a
   root `.mcp.json` (or `~/.claude.json` / `claude mcp add`). `.claude/mcp.json` is not
   auto-loaded, and `settings.json` has no `mcpServers` block. None of the five documented
   servers are actually active from this file.

4. **`settings.local.json` permissions are too broad** — `Bash(bash *)` auto-approves running
   any script (an effective bypass of the PreToolUse guard layer), `git add *` is loose, and
   there is a stray half-finished entry.

5. **`.gitignore` is empty**, though `hooks.md` instructs ignoring `.claude/audit.log` and
   `.claude/settings.local.json`. Current ignoring relies on a machine-global excludes file.

6. **No latency budget** — each Bash tool call fires up to ~6–8 `python` spawns across its
   hooks at ~93 ms each (~0.5–0.7 s of dead latency per command).

### Environment facts (verified)

- `python3`: MISSING. `python`: present at `C:\Program Files\Python314\python`.
- `jq`: MISSING.
- `python` cold-start ≈ 93 ms.
- Repo is currently single-module (root `pom.xml`, sources under `src/`).

---

## 2. Goals & non-goals

### Goals
- Every category ≥9.5.
- Guard hooks **fail closed** (block on doubt), advisory hooks **fail open** (no-op gracefully).
- Hook correctness is **verifiable** via a test harness, not merely asserted.
- Zero fragile per-hook interpreter assumptions.
- Reduce per-call hook latency.

### Non-goals (YAGNI)
- No new hook *types* — the project "Never" list is already well covered; hardening beats adding.
- No cross-platform abstraction layer — this is personal Windows config.
- No unrelated refactoring of skills/agents beyond correcting the module assumption.

---

## 3. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | JSON parsing via a shared `_lib.sh` sourced by all hooks | DRY; one place to fix; uniform fail-closed/open semantics |
| D2 | `json_field` uses sed/parameter-expansion (zero spawn) for top-level string fields; `python` fallback only for multiline `content` | Kills the `python3` bug AND the latency; `command`/`file_path` are simple strings |
| D3 | `resolve_module` returns nested `module/pom.xml` if present, else repo-root `pom.xml` | Works for current single-module repo and future monorepo |
| D4 | Guard hooks fail **closed**; advisory hooks fail **open** | A missing parser must never silently disable a safety guard |
| D5 | Move actually-used MCP servers (context7, github) to root `.mcp.json`; **slim** `.claude/mcp.json` to a documented "available servers" reference | `.mcp.json` is where Claude Code loads; keep the catalogue's documentation value |
| D6 | Rewrite `settings.local.json` with a tight `allow` list **and** a `deny` list mirroring dangerous patterns | Defense-in-depth; accept that out-of-allowlist commands prompt |
| D7 | Gate the 3 Maven-invoking PostToolUse hooks behind single-file / `CLAUDE_HOOK_SKIP_*` env flags | Bulk edits should not pay repeated Maven latency |
| D8 | Add a committed `.gitignore` | Don't rely on a machine-global excludes file in a template repo |

---

## 4. Components

### 4.1 `.claude/hooks/_lib.sh` (new — sourced, not executed)

Provides, with no external dependency beyond coreutils + optional `python`:

```sh
# Extract a top-level JSON string field. Zero process spawn for simple fields.
json_field <name>            # reads stdin already captured into $INPUT by caller

# Extract a possibly-multiline field (e.g. content), python fallback.
json_field_multiline <name>

# Resolve owning Maven module dir: nested module/pom.xml, else repo root.
resolve_module <file_path>   # echoes module dir or empty if no pom found

# Guard helpers
guard_block <message>        # prints message to stderr, exit 2
require_parse <raw_input>    # if raw non-empty but parse yields nothing -> guard_block
```

`json_field` implementation: pure `sed -n` against the captured `$INPUT`, matching
`"name"\s*:\s*"value"` and unescaping `\"`, `\\`, `\n`. No interpreter spawn.

### 4.2 `.claude/hooks/test/run-tests.sh` (new)

- Holds JSON fixtures (e.g. `rm -rf /`, `git commit` on main, a `.java` write,
  a secret in a diff, a tracked migration edit).
- Pipes each fixture into the relevant hook and asserts:
  - exit code (0 = allow, 2 = block),
  - presence/absence of `additionalContext` on stdout.
- Run manually and (optionally later) from CI. Exit non-zero on any mismatch.

### 4.3 Refactored hooks (all 16)

Each hook:
1. `INPUT=$(cat)`; `source "$(dirname "$0")/_lib.sh"`.
2. Field extraction via `json_field` / `json_field_multiline`.
3. Module resolution via `resolve_module` (where applicable).
4. Guard hooks call `require_parse "$INPUT"` early and `guard_block` on violation.

Specific hardening:
- `block-dangerous.sh`: `DELETE` pattern handles quoted and schema-qualified table names and
  optional trailing `;`; keep `rm -rf`/`-fr`, force-push, `git add -A`, `DROP`/`TRUNCATE`,
  bulk docker.
- `checkstyle-on-save.sh`, `flyway-validate.sh`, `verify-gate.sh`: use `resolve_module`;
  fall back to running without `-pl` when the module is the repo root (single-module).
- `checkstyle`/`avro generate-sources`/`flyway` PostToolUse hooks: skip when more than one
  file changed in the turn or when `CLAUDE_HOOK_SKIP_<NAME>=1`.

### 4.4 `.mcp.json` (new, repo root)

```json
{
  "mcpServers": {
    "context7": { "type": "stdio", "command": "npx", "args": ["-y", "@upstash/context7-mcp@latest"] },
    "github":   { "type": "url", "url": "https://api.githubcopilot.com/mcp/" }
  }
}
```
`github` documented as requiring `GITHUB_TOKEN`. postgres/schema-registry/jira remain
documented-but-inactive in the slimmed `.claude/mcp.json` reference.

### 4.5 `settings.local.json` (rewritten)

```json
{
  "permissions": {
    "allow": [
      "Bash(./mvnw *)",
      "Bash(git status)", "Bash(git diff *)", "Bash(git log *)",
      "Bash(git add -p)", "Bash(git restore *)"
    ],
    "deny": [
      "Bash(rm -rf *)", "Bash(git add -A)", "Bash(git add --all)",
      "Bash(git push --force *)"
    ]
  }
}
```
(Exact list finalised during implementation; principle = tight allow + dangerous deny.)

### 4.6 `.gitignore` (new)

```
.claude/audit.log
.claude/settings.local.json
.claude/session-checkpoint.md
sh.exe.stackdump
```

### 4.7 Skills & agents

Correct `./mvnw ... -pl <module>` references to match the single-module repo
(`./mvnw clean verify`), retaining a one-line note for the future monorepo case.
Affected: `skills/write`, `skills/test`, `skills/migrate`, `skills/review`, `skills/commit`,
and the corresponding agent files. Verify each skill/agent `allowed-tools` is minimal.

### 4.8 `hooks.md`

Document `_lib.sh`, the test harness, single+multi module resolution, the fail-closed/open
contract, and the updated MCP location.

---

## 5. Error handling & failure semantics

| Situation | Behaviour |
|---|---|
| `$INPUT` empty (no tool data) | All hooks `exit 0` (nothing to act on) |
| `$INPUT` present but field unparseable, **guard** hook | `guard_block` → `exit 2` (fail closed) |
| `$INPUT` present but field unparseable, **advisory** hook | `exit 0` (fail open, no false block) |
| No `python` for a multiline-only check | Advisory: `exit 0`; guard: never depends on python (sed only) |
| Module unresolvable (no pom at all) | Maven hooks `exit 0` (nothing to build) |

---

## 6. Testing strategy

- `run-tests.sh` asserts exit codes + `additionalContext` for every hook against fixtures.
- Manual acceptance on this machine:
  - `echo '{"command":"rm -rf /"}' | .claude/hooks/block-dangerous.sh` → exit 2.
  - `echo '{"command":"git commit -m x"}' | .claude/hooks/block-main-commit.sh` on `main` → exit 2.
  - `.java` write fixture → `checkstyle-on-save.sh` resolves root module, runs without `-pl`.
- No hook may pass tests while failing open on a violation fixture.

---

## 7. Acceptance criteria (per category → ≥9.5)

1. **Hook runtime:** every hook parses input without `python3`; guard fixtures all return
   exit 2; advisory fixtures return 0 with correct `additionalContext`; `run-tests.sh` green.
2. **Hook design:** `DELETE`/`git add` patterns hardened; each rule has a fixture.
3. **settings.json:** guards fail closed; Maven PostToolUse hooks gated against bulk-edit latency.
4. **MCP:** `context7` (and `github` with token) load from root `.mcp.json`; `/mcp` lists them.
5. **Skills / Agents:** verify commands run successfully on the single-module repo.
6. **Permissions:** `settings.local.json` has no `Bash(bash *)` / stray entry; allow tight; deny present.
7. **Docs:** `hooks.md` reflects `_lib.sh`, test harness, module resolution, fail-closed contract.
8. **.gitignore:** committed and effective.

---

## 8. Out of scope / follow-ups

- Wiring `run-tests.sh` into GitHub Actions (noted; not required for the score).
- Converting any hook to a native Windows (PowerShell) implementation — Git Bash is assumed.
