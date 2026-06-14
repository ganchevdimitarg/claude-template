#!/usr/bin/env bash
# PostToolUse — Write
# Runs flyway:validate after Claude writes a new migration file.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

echo "$FILE" | grep -qE 'db/migration/.*\.sql$' || exit 0

MODULE=$(echo "$FILE" | cut -d'/' -f1)
[ -f "$MODULE/pom.xml" ] || exit 0

OUTPUT=$(./mvnw flyway:validate -pl "$MODULE" -q 2>&1)
STATUS=$?

if [ $STATUS -ne 0 ]; then
  REASON=$(echo "$OUTPUT" | grep -E 'ERROR|WARN|FlywayException|Validate' | head -10)
  python3 -c "
import json, sys
f, r = sys.argv[1], sys.argv[2]
print(json.dumps({'additionalContext': f'Flyway validation failed after writing {f}:\n{r}\nCheck migration version, filename format (V<n>__<desc>.sql), and checksum.'}))
" "$FILE" "$REASON"
fi

exit 0
