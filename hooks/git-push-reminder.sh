#!/usr/bin/env bash
# PostToolUse hook for Edit|Write: reminds Claude to commit+push when a file
# inside a git repo is created or modified.
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Skip non-repo paths (memory, settings, .claude config)
case "$FILE_PATH" in
  */.claude/*|*/memory/*|*.env*|*credentials*|*secrets*) exit 0 ;;
esac

# Check if file is inside a git repo
REPO_ROOT=$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "")
[ -z "$REPO_ROOT" ] && exit 0

# Check if file is gitignored
cd "$REPO_ROOT"
git check-ignore -q "$FILE_PATH" 2>/dev/null && exit 0

# Check if there are uncommitted changes (the file we just wrote)
DIRTY=$(git status --porcelain -- "$FILE_PATH" 2>/dev/null || echo "")
[ -z "$DIRTY" ] && exit 0

REPO_NAME=$(basename "$REPO_ROOT")
echo "GIT-PUSH REMINDER: You wrote to ${REPO_NAME}/$(realpath --relative-to="$REPO_ROOT" "$FILE_PATH" 2>/dev/null || basename "$FILE_PATH") which has uncommitted changes. Commit and push before moving on."
exit 0
