#!/usr/bin/env bash
# Stop hook
# Runs ./mvnw verify (without clean) on modules with modified Java or SQL files.
# Uses 'clean' only as a fallback when verify fails, to rule out stale class issues.
# Exit 2 forces Claude to fix failures rather than stopping with a broken build.
#
# W5: Stop hooks have no file-based matcher in settings.json — the internal
# RELEVANT check below is the sole guard and runs as the very first operation.

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_ROOT" ] && exit 0

# W5: early-exit first — skip entirely if no Java or SQL files changed
# Covers unstaged, staged, and new untracked files
RELEVANT=$(
  {
    git diff --name-only 2>/dev/null
    git diff --cached --name-only 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | grep -E '\.(java|sql)$'
)
[ -z "$RELEVANT" ] && exit 0

# Derive unique top-level modules from all changed files
MODULES=$(
  {
    git diff --name-only 2>/dev/null
    git diff --cached --name-only 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | sed 's|/.*||' | sort -u
)

FAILED_MODULES=()

for MODULE in $MODULES; do
  [ -f "$REPO_ROOT/$MODULE/pom.xml" ] || continue

  # W5 performance: run verify without clean first (fast path)
  OUTPUT=$(cd "$REPO_ROOT" && ./mvnw verify -pl "$MODULE" -am -q 2>&1)
  STATUS=$?

  if [ $STATUS -ne 0 ]; then
    # Fallback: clean verify to rule out stale class files
    OUTPUT=$(cd "$REPO_ROOT" && ./mvnw clean verify -pl "$MODULE" -am -q 2>&1)
    STATUS=$?
  fi

  if [ $STATUS -ne 0 ]; then
    FAILED_MODULES+=("$MODULE")
    ERRORS=$(echo "$OUTPUT" | grep -E 'ERROR|FAILED|Tests run:.*Failures|BUILD' | head -15)
    echo "BUILD FAILURE in module: $MODULE" >&2
    echo "$ERRORS" >&2
  fi
done

if [ ${#FAILED_MODULES[@]} -gt 0 ]; then
  MODULES_STR="${FAILED_MODULES[*]}"
  python3 -c "
import json, sys
modules = sys.argv[1]
print(json.dumps({
  'additionalContext': (
    f'Build is RED in: {modules}. '
    'Fix all failures before stopping. '
    \"Run './mvnw verify -pl <module> -am' and address root causes — \"
    'do not suppress errors or skip tests.'
  )
}))
" "$MODULES_STR"
  exit 2
fi

exit 0
