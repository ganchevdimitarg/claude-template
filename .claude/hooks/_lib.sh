#!/usr/bin/env bash
# Shared helpers for .claude/hooks. SOURCE this file; do not execute it.
# Caller must set:  INPUT=$(cat)  before using *_field / emit_context.

# Resolve a python interpreter once (correctness fallback for parsing/emit).
_PY="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"

# json_field <name> — echo a top-level JSON string field from $INPUT.
# python-first (correct with escaped quotes), sed fallback when no python.
json_field() {
  local name="$1"
  if [ -n "$_PY" ]; then
    printf '%s' "${INPUT:-}" | "$_PY" -c '
import sys, json
name = sys.argv[1]
try:
    print(json.load(sys.stdin).get(name, ""))
except Exception:
    pass
' "$name" 2>/dev/null
    return
  fi
  # No python: best-effort sed for simple (unescaped) values.
  printf '%s' "${INPUT:-}" \
    | sed -n "s/.*\"$name\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
    | head -n1
}

# json_field_multiline <name> — for fields that may contain newlines (e.g. content).
json_field_multiline() {
  local name="$1"
  [ -n "$_PY" ] || return 0
  printf '%s' "${INPUT:-}" | "$_PY" -c '
import sys, json
name = sys.argv[1]
try:
    d = json.load(sys.stdin)
    print(d.get(name) or d.get("new_content") or d.get("content") or "")
except Exception:
    pass
' "$name" 2>/dev/null
}

# guard_field <name> — like json_field, but FAIL CLOSED:
# if the "name" key is present in raw $INPUT yet extraction is empty, block.
guard_field() {
  local name="$1" val
  val="$(json_field "$name")"
  if [ -z "$val" ] && printf '%s' "${INPUT:-}" | grep -q "\"$name\""; then
    echo "Blocked: safety hook could not parse '$name' from tool input (fail-closed)." >&2
    exit 2
  fi
  printf '%s' "$val"
}

# guard_block <message> — print to stderr and block.
guard_block() { echo "$1" >&2; exit 2; }

# resolve_module <file_path> — echo Maven module dir for the file:
#   nested "<seg>" when "<seg>/pom.xml" exists, else "." for the root pom, else empty.
resolve_module() {
  local file="$1" root seg
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  seg="${file%%/*}"
  if [ -n "$seg" ] && [ "$seg" != "$file" ] && [ -f "$root/$seg/pom.xml" ]; then
    printf '%s' "$seg"; return 0
  fi
  [ -f "$root/pom.xml" ] && printf '.'
}

# emit_context <message> — print {"additionalContext": "..."} to stdout (no block).
emit_context() {
  local msg="$1"
  if [ -n "$_PY" ]; then
    MSG="$msg" "$_PY" -c 'import os,json;print(json.dumps({"additionalContext":os.environ["MSG"]}))'
  else
    msg="${msg//\\/\\\\}"; msg="${msg//\"/\\\"}"; msg="${msg//$'\n'/\\n}"
    printf '{"additionalContext":"%s"}\n' "$msg"
  fi
}
