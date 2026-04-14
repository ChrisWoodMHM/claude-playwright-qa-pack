#!/usr/bin/env bash
#
# PostToolUse hook — blocks committed debugging artifacts and obvious secrets
# in spec/page-object files after any Write or Edit.
#
# Claude Code passes the tool-call payload on stdin as JSON. This script:
#   1. Extracts the file_path
#   2. Skips files that aren't test code
#   3. Greps for patterns that should never reach the repo
#   4. Exits 2 with a message on stderr — which Claude sees and must respond to
#
# Exit codes:
#   0 — all good, no action needed
#   2 — blocked: Claude must revise the write
set -euo pipefail

payload=$(cat)

# Extract file_path from the JSON payload. Tolerate malformed input.
file_path=$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    # file_path is passed at top level or inside tool_input depending on event shape
    tool_input = data.get("tool_input") or data
    print(tool_input.get("file_path", ""))
except Exception:
    pass
' 2>/dev/null || true)

# No path, nothing to check
if [[ -z "$file_path" ]]; then
  exit 0
fi

# Only inspect test-like TypeScript/JavaScript files
case "$file_path" in
  *.spec.ts|*.spec.js|*.test.ts|*.test.js) ;;
  */tests/pages/*.ts|*/tests/pages/*.js) ;;
  */tests/utils/*.ts|*/tests/utils/*.js) ;;
  *) exit 0 ;;
esac

# File may not exist yet if the tool call was rejected; bail gracefully.
if [[ ! -f "$file_path" ]]; then
  exit 0
fi

# Patterns that should never land in committed test code.
# Parallel arrays — regex patterns often contain `|` so we can't use it as a delimiter.
BLOCK_REGEXES=(
  'test\.only\(|test\.describe\.only\(|describe\.only\('
  'page\.pause\(\)'
  '(^|[^a-zA-Z_])debugger($|[^a-zA-Z_])'
  'Bearer [A-Za-z0-9\-_\.]{20,}'
  '(sk|pk)-[A-Za-z0-9]{20,}'
  '(password|apiKey|secret|token)[[:space:]]*[:=][[:space:]]*["\x27][A-Za-z0-9+/=_\-\.]{12,}["\x27]'
)

BLOCK_MESSAGES=(
  'Found test.only / describe.only — this silently skips the rest of the suite'
  'Found page.pause() — remove before committing; use --debug or the trace viewer instead'
  'Found `debugger` statement — remove before committing'
  'Found what looks like a Bearer token — credentials must come from env vars, not source'
  'Found what looks like an API key (sk-... / pk-...) — move to env vars'
  'Found a credential-shaped string literal — move to env vars'
)

violations=()

for i in "${!BLOCK_REGEXES[@]}"; do
  pattern="${BLOCK_REGEXES[$i]}"
  message="${BLOCK_MESSAGES[$i]}"
  if grep -E -nH "$pattern" "$file_path" >/dev/null 2>&1; then
    match_line=$(grep -E -nH "$pattern" "$file_path" | head -3)
    violations+=("$message"$'\n'"$match_line")
  fi
done

if (( ${#violations[@]} > 0 )); then
  {
    echo "QA Pack hook: blocked write to $file_path"
    echo ""
    for v in "${violations[@]}"; do
      echo "  ✗ $v"
      echo ""
    done
    echo "Revise the change to remove these patterns and try again."
  } >&2
  exit 2
fi

exit 0
