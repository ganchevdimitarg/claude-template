#!/usr/bin/env bash
# PreToolUse — Write|Edit (pom.xml files)
# Blocks adding a <dependency> with an inline <version> to a service pom.xml.
# All versions must be declared in the root BOM pom.xml.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)
CONTENT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('new_content') or d.get('content',''))" 2>/dev/null)

# Edit tool sends old_str/new_str — content will be empty; fall back to reading file from disk
if [ -z "$CONTENT" ] && [ -f "$FILE" ]; then
  CONTENT=$(cat "$FILE")
fi

echo "$FILE" | grep -qE 'pom\.xml$' || exit 0

# Only block service pom.xml files — not the root BOM itself
ROOT_POM=$(git rev-parse --show-toplevel 2>/dev/null)/pom.xml
[ "$FILE" = "$ROOT_POM" ] && exit 0
[ "$(realpath "$FILE" 2>/dev/null)" = "$(realpath "$ROOT_POM" 2>/dev/null)" ] && exit 0

# Scan the new content for <version> inside <dependency> blocks (not in <parent> or <plugin>)
python3 - << PYEOF
import sys, re, json

content = """$CONTENT"""

# Find dependency blocks containing <version>
dep_blocks = re.findall(r'<dependency>.*?</dependency>', content, re.DOTALL)
violations = []
for block in dep_blocks:
    if '<version>' in block:
        artifact = re.search(r'<artifactId>([^<]+)</artifactId>', block)
        version  = re.search(r'<version>([^<]+)</version>', block)
        art_name = artifact.group(1) if artifact else "unknown"
        ver_val  = version.group(1) if version else "unknown"
        # Allow properties like \${spring.version}
        if not ver_val.startswith('\${'):
            violations.append(f"  {art_name}: <version>{ver_val}</version>")

if violations:
    msg = (
        "Blocked: service pom.xml must not declare dependency versions inline.\n"
        "All versions must be managed in the root pom.xml BOM.\n"
        "Remove <version> from these dependencies (or move them to root BOM):\n"
        + "\n".join(violations)
    )
    print(json.dumps({"additionalContext": msg}))
    sys.exit(2)
PYEOF

STATUS=$?
exit $STATUS
