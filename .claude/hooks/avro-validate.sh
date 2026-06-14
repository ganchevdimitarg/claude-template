#!/usr/bin/env bash
# PostToolUse — Write|Edit
# Validates Avro schema files after Claude creates or edits them.
# Checks: valid JSON, required fields (type/name/namespace/fields), all fields have defaults.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

echo "$FILE" | grep -qE '\.avsc$' || exit 0
[ -f "$FILE" ] || exit 0

# W3: resolve project root for reliable mvnw path
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_ROOT" ] && exit 0

python3 - "$FILE" "$REPO_ROOT" << 'PYEOF'
import json, sys, subprocess

path      = sys.argv[1]
repo_root = sys.argv[2]
issues    = []

try:
    with open(path) as f:
        schema = json.load(f)
except json.JSONDecodeError as e:
    print(json.dumps({"additionalContext": f"Avro schema {path} is not valid JSON: {e}. Fix before proceeding."}))
    sys.exit(0)

if schema.get("type") != "record":
    issues.append("schema 'type' must be 'record'")
if not schema.get("name"):
    issues.append("schema is missing 'name'")
if not schema.get("namespace"):
    issues.append("schema is missing 'namespace' (required for Schema Registry subject naming)")

fields = schema.get("fields", [])
if not fields:
    issues.append("schema has no 'fields'")

no_default = [f.get("name", "?") for f in fields if "default" not in f]
if no_default:
    issues.append(
        f"fields missing 'default' (breaks BACKWARD compatibility): {', '.join(no_default)}. "
        "Add a default value to every field."
    )

if issues:
    msg = "\n".join(f"- {i}" for i in issues)
    print(json.dumps({"additionalContext": f"Avro schema issues in {path}:\n{msg}"}))
else:
    # Attempt generate-sources using absolute mvnw path from repo root
    result = subprocess.run(
        [f"{repo_root}/mvnw", "generate-sources", "-pl", "common-events", "-q"],
        capture_output=True, text=True, cwd=repo_root
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout)[:500]
        print(json.dumps({"additionalContext": f"Avro code generation failed after editing {path}:\n{err}"}))
PYEOF

exit 0
