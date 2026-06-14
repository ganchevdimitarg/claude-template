#!/usr/bin/env bash
# PreToolUse — Bash
# Blocks destructive shell commands before Claude executes them.
# Exit 2 → action blocked; stderr shown to Claude as the reason.

INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null)

block() { echo "$1" >&2; exit 2; }

# W3: rm -rf and rm -fr (both flag orderings)
echo "$CMD" | grep -qE '(^|\s|\/)rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive.*--force|--force.*--recursive)' && \
  block "Blocked: 'rm -rf' / 'rm -fr' is not permitted. Use 'rm' with explicit paths or 'git clean -fd' instead."

# Force-push to protected branches (origin main, origin/main, origin develop, origin/develop)
echo "$CMD" | grep -qE 'git\s+push.*--(force|force-with-lease)' && \
  echo "$CMD" | grep -qE '(origin\s+(main|develop|master)|origin/(main|develop|master))' && \
  block "Blocked: force-push to main/develop/master is not permitted."

# git add -A (stages everything including potential secrets)
echo "$CMD" | grep -qE 'git\s+add\s+(-A|--all)\b' && \
  block "Blocked: 'git add -A' is not permitted — stage explicit file paths instead."

# Destructive SQL executed directly (must go in Flyway migrations)
echo "$CMD" | grep -qiE '(DROP\s+TABLE|DROP\s+DATABASE|DROP\s+SCHEMA|TRUNCATE\s+TABLE)' && \
  block "Blocked: destructive SQL (DROP/TRUNCATE) must live in a Flyway migration, not executed directly via psql/mongo shell."

# DELETE without WHERE (full-table wipe)
echo "$CMD" | grep -qiE 'DELETE\s+FROM\s+[a-zA-Z_]+\s*;' && \
  block "Blocked: DELETE without WHERE clause detected — add a WHERE condition or use soft-delete (deleted_at = now())."

# Bulk Docker container teardown
echo "$CMD" | grep -qE 'docker\s+(rm|stop|kill)\s+\$\(docker\s+(ps|container)' && \
  block "Blocked: bulk Docker container removal/stop is not permitted in agentic sessions."

exit 0
