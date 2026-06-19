#!/usr/bin/env bash
# Stop hook — adaptive gate on modules with changed .java/.sql files:
#   • default          → ./mvnw test   (fast: compile + unit)
#   • IT/migration touched → ./mvnw verify (compile + unit + Failsafe integration)
# This keeps every turn fast while still catching integration/migration regressions
# on the turn that caused them. Full `clean verify` + checkstyle still runs at /commit.
# Build red → exit 2 forces Claude to fix rather than stop with a broken repo.
# Stop hooks have no file matcher; the RELEVANT check below is the sole guard.
. "$(dirname "$0")/_lib.sh"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_ROOT" ] && exit 0

CHANGED=$( {
  git diff --name-only 2>/dev/null
  git diff --cached --name-only 2>/dev/null
  git ls-files --others --exclude-standard 2>/dev/null
} | sort -u )

RELEVANT=$(echo "$CHANGED" | grep -E '\.(java|sql)$')
[ -z "$RELEVANT" ] && exit 0

# Phase selection: integration tests (Failsafe) and Flyway migrations are only validated
# by `verify`. If the turn touched an *IT.java / *IntegrationTest.java file or a
# db/migration/*.sql, run the full `verify`; otherwise fast `test` (compile + unit).
if echo "$RELEVANT" | grep -qE '(IT|IntegrationTest)\.java$|db/migration/.*\.sql$'; then
  GOAL="verify"; SCOPE="compile + unit + integration"
else
  GOAL="test";   SCOPE="compile + unit"
fi

# Resolve unique owning modules ( "." = root single-module ).
MODULES=$(for f in $RELEVANT; do resolve_module "$f"; echo; done | sort -u | grep -v '^$')

FAILED=()
for MODULE in $MODULES; do
  if [ "$MODULE" = "." ]; then PL=(); else PL=(-pl "$MODULE" -am); fi
  OUTPUT=$(cd "$REPO_ROOT" && ./mvnw "$GOAL" "${PL[@]}" -q 2>&1)
  if [ $? -ne 0 ]; then
    # Fallback: clean run to rule out stale class files.
    OUTPUT=$(cd "$REPO_ROOT" && ./mvnw clean "$GOAL" "${PL[@]}" -q 2>&1)
  fi
  if [ $? -ne 0 ]; then
    FAILED+=("$MODULE")
    echo "BUILD FAILURE in module: $MODULE" >&2
    echo "$OUTPUT" | grep -E 'ERROR|FAILED|Tests run:.*Failures|BUILD' | head -15 >&2
  fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
  emit_context "Build is RED in: ${FAILED[*]} ($SCOPE). Fix all failures before stopping. Run './mvnw $GOAL' and address root causes — do not suppress errors or skip tests."
  exit 2
fi
exit 0
