# MEMORY.md
# Auto-maintained by Claude Code — do not hand-edit.
# Claude updates this file to persist learned context across sessions.
# First 200 lines are loaded on session start. Keep entries concise.
# Format: [date] category: fact

## Project facts
- [2025-06] stack: Java 25 virtual threads, Spring Boot 4, WebMVC (not WebFlux except api-gateway)
- [2025-06] layout: single-module template (root pom, sources under src/); add business modules as <service-name> + shared common-events/common-test when scaling out
- [2025-06] infra: docker compose up -d starts PG:5432, Mongo:27017, Redis:6379, Kafka:9092, SchemaRegistry:8081
- [2025-06] build: ./mvnw clean verify -pl <module> -am
- [2025-06] records: default for all immutable types — @Value+@Builder only when record insufficient
- [2025-06] migrations: schema-first — Flyway migration before any Java code

## Solved problems
<!-- Claude appends here when resolving non-obvious issues -->

## Active work
- Branch: `docs/claude-config-hardening`
- No uncommitted files

## Team preferences
- Commit messages: Conventional Commits — feat/fix/chore/migration(scope): description
- PR: always draft first; checklist in PR body
- Branch naming: <type>/<scope>-<short-desc> e.g. feat/<service-name>-retry
