# claude-template

A **Claude Code configuration template** layered on a single-module Spring Boot 4 /
Java 25 skeleton. The Java app is intentionally minimal — the value of this repo is the
opinionated `.claude/` setup (conventions, skills, sub-agents, hooks, MCP wiring) that you
copy into a real project to make Claude Code productive and consistent from day one.

> The conventions in [`CLAUDE.md`](CLAUDE.md) describe a *target* microservice architecture
> (Kafka, MongoDB, api-gateway, sagas). Those sections are **aspirational** — apply them only
> once the corresponding module exists. Today this is a single Spring Boot module
> (`com.ganchevdimitarg.claudetemplate`).

## What's in here

| Area | Where | Purpose |
|---|---|---|
| Project conventions | [`CLAUDE.md`](CLAUDE.md) | Always-loaded context: stack, naming, security, testing, "never" rules |
| On-demand patterns | [`docs/context/`](docs/context/) | Detail files imported only when a task touches that area |
| Skills | `.claude/skills/` | `/write`, `/review`, `/commit`, `/test`, `/migrate`, `brainstorming` |
| Sub-agents | `.claude/agents/` | code-writer, code-reviewer, git-agent, test-agent, scaffold-agent, debug-agent, performance-agent |
| Hooks | `.claude/hooks/` | Lifecycle scripts (git context injection, checkstyle, session checkpoint) |
| MCP servers | `.claude/mcp.json`, `.mcp.json` | context7 (live docs) + code-review-graph (knowledge graph) |
| Decisions | [`docs/decisions.md`](docs/decisions.md), [`docs/adr/`](docs/adr/) | Running decision log and Architecture Decision Records |

## Stack

- **Java 25** · virtual threads · records-first
- **Spring Boot 4** (`spring-boot-starter-parent` 4.1.0) · WebMVC
- **Maven** via the bundled wrapper (`./mvnw`)

## Prerequisites

- JDK 25
- **Windows**: Git Bash on `PATH` — the Claude Code hooks are bash scripts. Verify with
  `bash --version`. See [`SETUP.md`](SETUP.md) for the full setup.

## Quick start

```bash
# Run the application
./mvnw spring-boot:run

# Build and run tests
./mvnw clean verify
```

## Using this as a template

1. Copy [`CLAUDE.md`](CLAUDE.md), `docs/context/`, and `.claude/` into your project.
2. Follow [`SETUP.md`](SETUP.md) for file placement, `.gitignore` entries, hook
   permissions (`chmod +x .claude/hooks/*.sh`), and MCP environment variables.
3. Trim the aspirational sections of `CLAUDE.md` down to the modules you actually have.
4. Give each new module its own `CLAUDE.md` as the repo grows.

## Repository layout

```
/
├── CLAUDE.md            ← master context (imports docs/context/* on demand)
├── MEMORY.md            ← Claude's auto-maintained scratchpad
├── SETUP.md             ← placement + setup guide
├── pom.xml              ← single-module dependencies
├── mvnw / mvnw.cmd      ← Maven wrapper
├── docs/
│   ├── decisions.md     ← running decision log
│   ├── adr/             ← Architecture Decision Records
│   └── context/         ← @import targets (loaded on demand)
├── src/                 ← Spring Boot application + tests
└── .claude/             ← agents, skills, context, hooks, MCP config
```

See [`docs/context/project-layout.md`](docs/context/project-layout.md) for the full layout.
