#!/usr/bin/env bash
# PostToolUse — Write|Edit (controller Java files)
# After Claude edits a @RestController, checks that all @RequestMapping paths
# follow the /api/v{n}/ versioning convention.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

echo "$FILE" | grep -qE '\.java$' || exit 0
[ -f "$FILE" ] || exit 0
grep -qE '@RestController|@Controller' "$FILE" || exit 0

python3 - "$FILE" << 'PYEOF'
import re, sys, json

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# Extract all @RequestMapping / @GetMapping / @PostMapping etc. path values
mappings = re.findall(r'@(?:Request|Get|Post|Put|Patch|Delete)Mapping\s*\(\s*(?:value\s*=\s*)?["\']([^"\']+)["\']', content)
# Also catch @RequestMapping on the class itself
class_mappings = re.findall(r'@RequestMapping\s*\(\s*["\']([^"\']+)["\']', content)
all_paths = mappings + class_mappings

violations = []
for p in all_paths:
    if p.startswith('/actuator') or p.startswith('/error'):
        continue
    if not re.match(r'^/api/v\d+/', p) and not p.startswith('/api/v'):
        violations.append(f"  '{p}' — expected /api/v{{n}}/...")

if violations:
    msg = (
        f"API versioning violation in {path}:\n"
        + "\n".join(violations)
        + "\nAll endpoints must use /api/v{n}/ prefix. See CLAUDE.md ## Architecture."
    )
    print(json.dumps({"additionalContext": msg}))
PYEOF

exit 0
