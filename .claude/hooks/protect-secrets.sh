#!/usr/bin/env bash
# PreToolUse — Read|Write|Edit|Bash
# Blocks any tool access to secrets files.
# Scans both file_path (for Read/Write/Edit) and full command string (for Bash).

INPUT=$(cat)

# Extract both fields; scan the entire command string for Bash tool calls
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)
CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null)

# Combine both into a single target for pattern matching
TARGET="${FILE_PATH} ${CMD}"

PATTERNS=(
  '\.env(\.|$)'
  '\.pem(\s|$)'
  '\.key(\s|$)'
  '\.p12(\s|$)'
  '\.pfx(\s|$)'
  '\.jks(\s|$)'
  '[^a-z]secrets?\.'
  '[^a-z]credentials?[^a-z]'
  'id_rsa'
  'id_ed25519'
  'id_ecdsa'
  'application-prod(uction)?\.ya?ml'
)

for p in "${PATTERNS[@]}"; do
  echo "$TARGET" | grep -qiE "$p" && {
    echo "Blocked: access to a secrets/credentials file is not permitted." >&2
    echo "  Matched pattern: $p" >&2
    echo "  Target: ${FILE_PATH:-$CMD}" >&2
    echo "Store secrets in environment variables or a secrets manager (e.g. Vault, AWS SSM) — never in files Claude can read/write." >&2
    exit 2
  }
done

exit 0
