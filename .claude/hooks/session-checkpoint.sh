#!/usr/bin/env bash
# PostToolUse — triggered after /compact
# Saves session state to .claude/session-checkpoint.md so Claude can resume
# after context compaction without losing thread.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Only fire after compact operations
echo "$TOOL" | grep -qiE "compact|clear" || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
RECENT=$(git log --oneline -5 2>/dev/null || echo "none")
UNCOMMITTED=$(git diff --name-only 2>/dev/null | head -20)
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

cat > "$REPO_ROOT/.claude/session-checkpoint.md" << CHECKPOINT
# Session checkpoint — $TIMESTAMP

## Branch
$BRANCH

## Recent commits
$RECENT

## Uncommitted files at checkpoint
$UNCOMMITTED

## Resume instruction
Read this file at the start of the next session to resume context.
Check git status and the above branch/commits to understand where work stopped.
CHECKPOINT

echo "Session checkpoint saved to .claude/session-checkpoint.md" >&2
exit 0
