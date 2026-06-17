# Claude Code setup — where everything goes

## Prerequisites

**Windows users**: hooks are bash scripts and require **Git Bash** in `PATH`.
Install [Git for Windows](https://git-scm.com/download/win) and ensure `bash.exe` is available before running Claude Code.
Verify with: `bash --version`

After cloning, run once:
```bash
chmod +x .claude/hooks/*.sh
```

## File placement

| File / dir | Location | Commit? |
|---|---|---|
| `CLAUDE.md` | repo root | ✅ |
| `MEMORY.md` | repo root | ✅ (Claude maintains it) |
| `SETUP.md` | repo root | ✅ |
| `.gitignore` | repo root | ✅ |
| `docs/decisions.md` | repo root | ✅ |
| `docs/adr/*.md` | repo root | ✅ |
| `docs/sagas/*.md` | repo root | ✅ |
| `docs/context/*.md` | repo root | ✅ (@import targets) |
| `<module>/CLAUDE.md` | each service dir | ✅ |
| `.claude/settings.json` | repo root | ✅ (team hooks) |
| `.claude/mcp.json` | repo root | ✅ |
| `.claude/hooks.md` | repo root | ✅ |
| `.claude/agents/*.md` | repo root | ✅ |
| `.claude/skills/*/SKILL.md` | repo root | ✅ |
| `.claude/context/*.md` | repo root | ✅ |
| `.claude/hooks/*.sh` | repo root | ✅ |
| `.claude/settings.local.json` | repo root | ❌ gitignore |
| `.claude/audit.log` | repo root | ❌ gitignore |
| `.claude/session-checkpoint.md` | repo root | ❌ gitignore |
| `user-CLAUDE.md` | copy to `~/.claude/CLAUDE.md` | ❌ personal, outside repo |

## Add to .gitignore
```
.claude/audit.log
.claude/settings.local.json
.claude/session-checkpoint.md
```

## MCP setup
Set these env vars before connecting MCP servers (see `.claude/mcp.json`):
```bash
export GITHUB_TOKEN=<repo-scoped-token>
export POSTGRES_MCP_URL=postgresql://user:pass@localhost:5432/dbname
# optional:
export SCHEMA_REGISTRY_MCP_URL=<url>
export JIRA_MCP_URL=<url>
export JIRA_TOKEN=<token>
```

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
