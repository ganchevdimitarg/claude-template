# Setting up Claude Code in your repo

This template ships an opinionated `.claude/` configuration — conventions, skills,
sub-agents, lifecycle hooks, and MCP wiring. Follow the steps below to copy it into another
repository and get a working setup. Steps 1–5 are the minimum; 6–8 adapt it to your stack.

> **Windows users**: every hook is a Bash script and needs **Git Bash** on `PATH`. Install
> [Git for Windows](https://git-scm.com/download/win) and verify with `bash --version`
> *before* starting Claude Code, or the hooks will silently no-op.

---

## What gets copied

| Item | Path | Purpose |
|---|---|---|
| Master context | `CLAUDE.md` | Always-loaded conventions (imports `docs/context/*` on demand) |
| On-demand patterns | `docs/context/` | Detail files loaded only when a task touches that area |
| Skills | `.claude/skills/` | `/write`, `/review`, `/commit`, `/test`, `/migrate`, `brainstorming` |
| Sub-agents | `.claude/agents/` | code-writer, code-reviewer, git-agent, test-agent, scaffold-agent, debug-agent, performance-agent |
| Hooks | `.claude/hooks/` | Lifecycle scripts wired in `settings.json` |
| Team hook wiring | `.claude/settings.json` | Committed; wires the hooks |
| MCP servers (live) | `.mcp.json` (repo root) | The file Claude Code actually loads |
| MCP catalogue | `.claude/mcp.json` | Reference only — **not** loaded by Claude Code |
| Local settings template | `.claude/settings.local.example.json` | Copy to `settings.local.json` (gitignored) |
| Decisions | `docs/decisions.md`, `docs/adr/` | Decision log + Architecture Decision Records |

---

## Step 1 — Copy the config into your repo

From a checkout of this template, copy into your target repo root:

```bash
TARGET=/path/to/your-repo

cp -r .claude/ "$TARGET/"
cp -r docs/context/ "$TARGET/docs/"
cp .mcp.json CLAUDE.md "$TARGET/"
```

Optional but recommended:

```bash
cp -r docs/adr/ docs/sagas/ "$TARGET/docs/"
cp docs/decisions.md MEMORY.md SETUP.md "$TARGET/"
```

> Do **not** copy `.claude/audit.log`, `.claude/settings.local.json`, or
> `.claude/session-checkpoint.md` — they are per-machine and gitignored (see Step 4).

## Step 2 — Make the hooks executable

```bash
cd "$TARGET"
chmod +x .claude/hooks/*.sh .claude/hooks/test/*.sh
```

## Step 3 — Create your local settings

`settings.json` (committed) wires the hooks for everyone; `settings.local.json` (gitignored)
holds *your* machine-specific permission allows and which MCP servers you enable.

```bash
cp .claude/settings.local.example.json .claude/settings.local.json
```

The example is a safe minimal baseline: a tight permission allow-list, a deny-list for
dangerous commands, and `enabledMcpjsonServers` (`context7`, `github`, `code-review-graph`).
Keep allows narrow — never blanket `Bash(git *)` or whole-drive `Read(...)`.

## Step 4 — Update `.gitignore`

```
# Claude Code — local only, never commit
.claude/audit.log
.claude/settings.local.json
.claude/session-checkpoint.md
```

## Step 5 — Adapt `CLAUDE.md` to your project

`CLAUDE.md` describes a *target* microservice architecture; large parts (Kafka, MongoDB,
api-gateway, sagas, Avro) are aspirational. Trim it down to the modules you actually have,
fix the package name and stack lines, and update the naming-convention examples. Give each
module its own `CLAUDE.md` as the repo grows.

## Step 6 — Prune hooks to your stack

`.claude/settings.json` wires all hooks below. Keep the generic ones; **remove the
stack-specific entries** (and their script files) if they don't apply to your project.

| Keep anywhere (generic) | Java / Maven / Spring-specific — remove if N/A |
|---|---|
| `inject-git-context` (git context on session start) | `checkstyle-on-save` |
| `secret-scan`, `protect-secrets` | `flyway-validate`, `protect-migrations` |
| `block-dangerous` | `avro-validate` |
| `block-main-commit` | `api-contract-check` |
| `audit-log` | `n-plus-one-check` |
| `session-checkpoint` | `verify-gate` (runs `./mvnw clean verify`) |
| `warn-generated-files` | `dependency-check` (checks root `pom.xml` BOM) |

To drop a hook: delete its entry from `settings.json` **and** its `.sh` file. Leave
`_lib.sh` (shared helpers) in place. See `.claude/hooks.md` for what each hook does.

## Step 7 — Set up MCP servers

The **root `.mcp.json`** is the file Claude Code loads (`.claude/mcp.json` is a reference
catalogue only). A server is live only when it is in `.mcp.json` **and** listed under
`enabledMcpjsonServers` in `settings.local.json`. The shipped servers:

- **context7** — live library docs. Needs `npx` (Node) on `PATH`; no token.
- **github** — read PRs/issues/CI. Uses the URL transport; may prompt for OAuth on first
  connect, or set `GITHUB_TOKEN` (repo scope). Remove if unused.
- **code-review-graph** — local knowledge graph backing the review/explore skills.
  Install with `pip install code-review-graph` and ensure it is on `PATH` (otherwise set
  `command` in `.mcp.json` to the absolute path of `code-review-graph.exe`). Then build the
  graph once per repo:
  ```bash
  code-review-graph build      # creates .code-review-graph/
  ```

Catalogue-only servers (`postgres`, `schema-registry`, `jira`) are documented in
`.claude/mcp.json`; enable them by adding a block to `.mcp.json`, listing them in
`enabledMcpjsonServers`, and exporting their env vars.

## Step 8 — Verify

```bash
claude mcp list      # enabled servers show as connected
```

Then start Claude Code and confirm:

1. **Session start** → `inject-git-context.sh` fires (the current branch name appears in context).
2. **Edit a tracked file** → the relevant PostToolUse hook output appears in the turn
   (e.g. `checkstyle-on-save` on a `.java` edit, if you kept it).
3. **Run `/review`** → the review skill loads and prints its checklist header.

If a hook never fires on Windows, re-check that `bash --version` works in the shell Claude
Code launches.

---

## File placement reference

| File / dir | Location | Commit? |
|---|---|---|
| `CLAUDE.md` | repo root | ✅ |
| `MEMORY.md` | repo root | ✅ (Claude maintains it) |
| `SETUP.md` | repo root | ✅ |
| `.gitignore` | repo root | ✅ |
| `.mcp.json` | repo root | ✅ (live MCP config) |
| `docs/decisions.md`, `docs/adr/*`, `docs/sagas/*`, `docs/context/*` | repo root | ✅ |
| `<module>/CLAUDE.md` | each module dir | ✅ |
| `.claude/settings.json` | `.claude/` | ✅ (team hook wiring) |
| `.claude/mcp.json` | `.claude/` | ✅ (reference catalogue) |
| `.claude/hooks.md` | `.claude/` | ✅ |
| `.claude/agents/*.md`, `.claude/skills/*/SKILL.md`, `.claude/context/*.md` | `.claude/` | ✅ |
| `.claude/hooks/*.sh` | `.claude/hooks/` | ✅ |
| `.claude/settings.local.example.json` | `.claude/` | ✅ (template) |
| `.claude/settings.local.json` | `.claude/` | ❌ gitignore |
| `.claude/audit.log` | `.claude/` | ❌ gitignore |
| `.claude/session-checkpoint.md` | `.claude/` | ❌ gitignore |
| `~/.claude/CLAUDE.md` | your home dir | ❌ personal, outside repo |
