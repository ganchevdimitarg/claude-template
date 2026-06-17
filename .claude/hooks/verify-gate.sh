#!/usr/bin/env bash
# Stop hook. Runs ./mvnw verify on modules with changed .java/.sql files.
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

# Resolve unique owning modules ( "." = root single-module ).
MODULES=$(for f in $RELEVANT; do resolve_module "$f"; echo; done | sort -u | grep -v '^$')

FAILED=()
for MODULE in $MODULES; do
  if [ "$MODULE" = "." ]; then PL=(); else PL=(-pl "$MODULE" -am); fi
  OUTPUT=$(cd "$REPO_ROOT" && ./mvnw verify "${PL[@]}" -q 2>&1)
  if [ $? -ne 0 ]; then
    # Fallback: clean verify to rule out stale class files.
    OUTPUT=$(cd "$REPO_ROOT" && ./mvnw clean verify "${PL[@]}" -q 2>&1)
  fi
  if [ $? -ne 0 ]; then
    FAILED+=("$MODULE")
    echo "BUILD FAILURE in module: $MODULE" >&2
    echo "$OUTPUT" | grep -E 'ERROR|FAILED|Tests run:.*Failures|BUILD' | head -15 >&2
  fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
  emit_context "Build is RED in: ${FAILED[*]}. Fix all failures before stopping. Run './mvnw verify' and address root causes — do not suppress errors or skip tests."
  exit 2
fi
exit 0
