#!/usr/bin/env bash
# PreToolUse — Write|Edit
# Blocks Claude from overwriting generated files before the write happens.
# Generated files: target/generated-sources paths, or files annotated with @Generated.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

[ -z "$FILE" ] && exit 0

# Block writes to generated-sources directories
echo "$FILE" | grep -qE '(target/generated-sources|target/generated-test-sources)' && {
  python3 -c "
import json, sys
f = sys.argv[1]
msg = (
  f'Blocked: {f!r} is inside target/generated-sources — this file is auto-generated and will be overwritten on next build.\n'
  'Edit the source instead:\n'
  '- Avro classes  → edit .avsc in common-events/src/main/avro/ then run: ./mvnw generate-sources -pl common-events\n'
  '- Lombok        → edit the @Lombok annotation on the source class\n'
  '- MapStruct     → edit the mapper interface or @Mapper configuration'
)
print(json.dumps({'additionalContext': msg}))
" "$FILE"
  exit 2
}

# Block writes to Java files that already contain @Generated annotation
echo "$FILE" | grep -qE '\.java$' && [ -f "$FILE" ] && \
  grep -qE '@Generated|@javax\.annotation\.Generated|@jakarta\.annotation\.Generated' "$FILE" && {
  python3 -c "
import json, sys
f = sys.argv[1]
print(json.dumps({'additionalContext': f'Blocked: {f!r} contains @Generated — this file is auto-generated. Edit the source template or annotation instead, then regenerate.'}))
" "$FILE"
  exit 2
}

exit 0
