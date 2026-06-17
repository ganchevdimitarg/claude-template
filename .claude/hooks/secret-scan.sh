#!/usr/bin/env bash
# PreToolUse — Bash (git commit)
# Scans staged file CONTENT for secrets before every commit.
# Distinct from protect-secrets.sh (which guards file paths) —
# this guards what is inside files, catching inline credentials.

INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null)

echo "$CMD" | grep -qE 'git\s+commit' || exit 0

# Guard: skip in repos with no commits (detached HEAD, fresh init)
git rev-parse HEAD > /dev/null 2>&1 || exit 0

DIFF=$(git diff --staged 2>/dev/null)
[ -z "$DIFF" ] && exit 0

python3 - << 'PYEOF'
import subprocess, sys, re, json

result = subprocess.run(["git", "diff", "--staged"], capture_output=True, text=True)
diff = result.stdout

patterns = {
    "AWS Access Key":          r'AKIA[0-9A-Z]{16}',
    "AWS Secret Key":          r'(?i)aws.{0,20}secret.{0,20}["\']?[A-Za-z0-9/+=]{40}',
    "Private key header":      r'-----BEGIN (RSA|EC|DSA|OPENSSH) PRIVATE KEY-----',
    "JWT token":               r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',
    "Generic password in YAML": r'(?i)(password|passwd|secret|credentials?)\s*[:=]\s*["\']?(?!(\$\{|<|your|change|example|placeholder|test|dummy))[A-Za-z0-9!@#$%^&*]{8,}',
    "DB connection string":    r'(?i)(jdbc:[a-z]+://[^"\';\s]*:[^"\';\s@]+@)',
    "Generic API key":         r'(?i)(api[_-]?key|apikey|api[_-]?secret)\s*[:=]\s*["\']?[A-Za-z0-9_\-]{16,}',
    "Spring datasource password": r'(?i)spring\.datasource\.password\s*[:=]\s*(?!(\$\{|<))\S+',
}

hits = []
for name, pattern in patterns.items():
    for match in re.finditer(pattern, diff):
        line_num = diff[:match.start()].count('\n') + 1
        hits.append(f"  [{name}] line ~{line_num}: {match.group()[:60]}...")

if hits:
    msg = "Blocked: potential secrets detected in staged changes:\n" + "\n".join(hits)
    msg += "\n\nRemove secrets before committing. Use environment variables or a secrets manager."
    print(json.dumps({"additionalContext": msg}))
    sys.exit(2)
PYEOF

STATUS=$?
exit $STATUS
