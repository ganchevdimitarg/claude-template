# ~/.claude/CLAUDE.md
# Personal preferences — applies to ALL projects.
# Copy this file to ~/.claude/CLAUDE.md

## Language & style
- British English for prose and comments
- Concise commit messages — no fluff words ("Refactor", "Update", "Fix" are enough context with Conventional Commits type)
- Never use // TODO without a ticket reference

## Personal tooling
- Editor: IntelliJ IDEA — generate run configs as `.run/*.xml` when creating new services
- Terminal: iTerm2 — use ANSI colour codes in scripts
- Prefer `./mvnw` over `mvn` — always use wrapper

## Output preferences
- Code examples: always include imports
- Explanations: start with the "why", then the "how"
- When multiple approaches exist: show the preferred one first, mention alternatives briefly

## Session behaviour
- Always read MEMORY.md at session start if it exists in the project root
- Always read docs/decisions.md before proposing architectural changes
- Confirm the subject line of commit messages with me before committing
- Use /effort high for architecture, debugging, and migration planning; /effort low for simple edits
