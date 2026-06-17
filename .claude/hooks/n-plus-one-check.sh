#!/usr/bin/env bash
# PostToolUse — Write|Edit (repository and entity Java files)
# Scans for common N+1 query patterns after Claude writes a JPA repository or entity.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

echo "$FILE" | grep -qE '\.java$' || exit 0
[ -f "$FILE" ] || exit 0

python3 - "$FILE" << 'PYEOF'
import re, sys, json

path = sys.argv[1]
with open(path) as f:
    content = f.read()

warnings = []

# findAll() without pagination — matches Java interface methods, Spring Data repos, and Kotlin
if re.search(r'(?:fun|List<?[^>]*>?|Iterable<?[^>]*>?)\s+findAll\s*\(\s*\)', content):
    if 'Pageable' not in content and 'Page<' not in content:
        warnings.append(
            "findAll() without Pageable detected — unbounded query will load entire table. "
            "Add Pageable parameter or a WHERE clause."
        )

# @OneToMany or @ManyToMany without explicit fetch type
for match in re.finditer(r'@(OneToMany|ManyToMany)(?!\s*\()', content):
    warnings.append(
        f"@{match.group(1)} without fetch = FetchType.LAZY — defaults vary by provider. "
        "Declare fetch type explicitly to avoid accidental eager loading."
    )

# @OneToMany(fetch = EAGER)
for match in re.finditer(r'@(OneToMany|ManyToMany)\s*\([^)]*fetch\s*=\s*(?:FetchType\.)?EAGER', content):
    warnings.append(
        f"@{match.group(1)}(fetch = EAGER) triggers N+1 queries on every parent load. "
        "Use LAZY + @EntityGraph on the repository query instead."
    )

# @ManyToOne without @EntityGraph hint where used in a collection loop
if '@ManyToOne' in content and 'findAll' in content and '@EntityGraph' not in content:
    warnings.append(
        "@ManyToOne detected alongside findAll — potential N+1. "
        "Use @EntityGraph on the repository query to join-fetch associations."
    )

if warnings:
    msg = f"N+1 / performance warnings in {path}:\n" + "\n".join(f"- {w}" for w in warnings)
    print(json.dumps({"additionalContext": msg}))
PYEOF

exit 0
