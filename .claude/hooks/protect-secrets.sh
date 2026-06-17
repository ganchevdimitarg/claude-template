#!/usr/bin/env bash
# PreToolUse — Read|Write|Edit|Bash. Blocks tool access to secrets files. Fail-closed.
INPUT=$(cat)
. "$(dirname "$0")/_lib.sh"

guard_require file_path   # fail-closed if a key is present but unparseable
guard_require command
FILE_PATH="$(json_field file_path)"
CMD="$(json_field command)"
TARGET="${FILE_PATH}${CMD:+ $CMD}"

PATTERNS=(
  '\.env(\.|$)' '\.pem(\s|$)' '\.key(\s|$)' '\.p12(\s|$)' '\.pfx(\s|$)' '\.jks(\s|$)'
  '[^a-z]secrets?\.' '[^a-z]credentials?[^a-z]' 'id_rsa' 'id_ed25519' 'id_ecdsa'
  'application-prod(uction)?\.ya?ml'
)
for p in "${PATTERNS[@]}"; do
  echo "$TARGET" | grep -qiE "$p" && \
    guard_block "Blocked: access to a secrets/credentials file is not permitted (matched: $p). Use env vars or a secrets manager."
done
exit 0
