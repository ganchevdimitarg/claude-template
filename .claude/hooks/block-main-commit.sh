#!/usr/bin/env bash
# PreToolUse — Bash
# Blocks 'git commit' when on main or develop branch.

INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null)

echo "$CMD" | grep -qE 'git\s+commit' || exit 0

BRANCH=$(git branch --show-current 2>/dev/null)

case "$BRANCH" in
  main|develop|master)
    cat >&2 << MSG
Blocked: direct commits to '$BRANCH' are not permitted.
Create a feature branch first:
  git checkout -b <type>/<scope>-<short-desc>
  e.g. git checkout -b feat/order-service-retry
MSG
    exit 2
    ;;
esac

exit 0
