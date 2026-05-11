#!/usr/bin/env bash
# PostToolUse hook for Edit|Write: logs the specific file path to a session tracking file.
# The check-unpushed.sh Stop hook reads this file to check only these specific files.
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

# Skip non-repo paths
case "$FILE_PATH" in
  /tmp/*|*/.claude/projects/*) exit 0 ;;
esac

# Find repo root
REPO_ROOT=$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "")
[ -z "$REPO_ROOT" ] && exit 0

# Skip if file is gitignored
cd "$REPO_ROOT"
git check-ignore -q "$FILE_PATH" 2>/dev/null && exit 0

# Log both repo root and the specific file (tab-separated)
echo "${REPO_ROOT}	${FILE_PATH}" >> "/tmp/claude-repos-touched-${SESSION_ID}"
exit 0
