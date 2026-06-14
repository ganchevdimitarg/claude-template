#!/usr/bin/env bash
# PreToolUse — Write|Edit
# Blocks editing a Flyway migration that has already been committed to git.
# New (untracked) migration files are always allowed.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

# Only care about versioned migration files
echo "$FILE" | grep -qE 'db/migration/V[0-9]+__.*\.sql$' || exit 0

# Allow if file does not yet exist in git history (new migration)
git ls-files --error-unmatch "$FILE" 2>/dev/null || exit 0

# File is tracked — block the edit
cat >&2 << 'MSG'
Blocked: editing a committed Flyway migration is not permitted.
Committed migrations are immutable — their checksums are recorded in flyway_schema_history.
To make a schema change, create a new versioned migration:
  V<n+1>__<description>.sql
MSG
exit 2
