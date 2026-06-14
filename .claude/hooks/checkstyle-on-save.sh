#!/usr/bin/env bash
# PostToolUse — Write|Edit
# Runs Checkstyle immediately after Claude writes/edits a Java file.
# Feeds violations back as additionalContext so Claude fixes them inline.
# No debounce — Checkstyle handles incomplete files with parse errors natively.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

echo "$FILE" | grep -qE '\.java$' || exit 0

[ -f "$FILE" ] || exit 0

# Derive maven module from file path (top-level directory)
MODULE=$(echo "$FILE" | cut -d'/' -f1)
[ -f "$MODULE/pom.xml" ] || exit 0

# Escape hatch: CLAUDE_HOOK_SKIP_CHECKSTYLE=1 disables for bulk-edit sessions
[ "${CLAUDE_HOOK_SKIP_CHECKSTYLE:-0}" = "1" ] && exit 0

OUTPUT=$(./mvnw checkstyle:check -pl "$MODULE" -q 2>&1)
STATUS=$?

if [ $STATUS -ne 0 ]; then
  VIOLATIONS=$(echo "$OUTPUT" | grep -E '\[WARN\]|\[ERROR\]' | head -20)
  python3 -c "
import json, sys
f, v = sys.argv[1], sys.argv[2]
print(json.dumps({'additionalContext': f'Checkstyle violations in {f}:\n{v}\nFix before proceeding.'}))
" "$FILE" "$VIOLATIONS"
fi

exit 0
