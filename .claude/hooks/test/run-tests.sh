#!/usr/bin/env bash
# Test harness for .claude/hooks. Pipes JSON fixtures into hooks and asserts exit codes.
set -u
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

# assert_exit <desc> <expected_code> <hook-file> <json-input>
assert_exit() {
  local desc="$1" exp="$2" hook="$3" json="$4" code
  printf '%s' "$json" | "$HOOKS_DIR/$hook" >/tmp/hook_out 2>/tmp/hook_err
  code=$?
  if [ "$code" = "$exp" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $desc — exit $code, expected $exp"
    echo "  stderr: $(head -c 200 /tmp/hook_err)"
  fi
}

# assert_lib <desc> <expected> <command...>  (sources _lib.sh, runs a snippet)
assert_lib() {
  local desc="$1" exp="$2"; shift 2
  local got
  got="$("$@")"
  if [ "$got" = "$exp" ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); echo "FAIL: $desc — got '$got', expected '$exp'"; fi
}

# --- _lib.sh unit checks ---
lib_json() { INPUT="$1"; . "$HOOKS_DIR/_lib.sh"; json_field "$2"; }

assert_lib "json_field command simple"   "git status"            lib_json '{"command":"git status"}' command
assert_lib "json_field file_path"        "src/Main.java"         lib_json '{"file_path":"src/Main.java"}' file_path
assert_lib "json_field windows path"     'D:\IdeaProjects\x.java' lib_json '{"file_path":"D:\\IdeaProjects\\x.java"}' file_path
assert_lib "json_field absent -> empty"  ""                      lib_json '{"command":"x"}' file_path

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
