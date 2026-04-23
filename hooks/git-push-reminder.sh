#!/usr/bin/env bash
# PostToolUse hook for Edit|Write: warns when a file is written outside a git
# repo, and reminds to commit+push when inside a repo but uncommitted.
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Skip paths that legitimately live outside repos
case "$FILE_PATH" in
  */.claude/*|*/memory/*|*.env*|*credentials*|*secrets*|/tmp/*) exit 0 ;;
esac

# Check if file is inside a git repo
REPO_ROOT=$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$REPO_ROOT" ]; then
  FNAME=$(basename "$FILE_PATH")
  echo "NOT IN A GIT REPO: You wrote '${FNAME}' to $(dirname "$FILE_PATH") which is outside any git repository. Move it into an appropriate repo, commit, and push. Files outside repos don't persist across sessions."
  exit 0
fi

# Check if file is gitignored
cd "$REPO_ROOT"
git check-ignore -q "$FILE_PATH" 2>/dev/null && exit 0

# Check if there are uncommitted changes (the file we just wrote)
DIRTY=$(git status --porcelain -- "$FILE_PATH" 2>/dev/null || echo "")
[ -z "$DIRTY" ] && exit 0

REPO_NAME=$(basename "$REPO_ROOT")
echo "GIT-PUSH REMINDER: You wrote to ${REPO_NAME}/$(realpath --relative-to="$REPO_ROOT" "$FILE_PATH" 2>/dev/null || basename "$FILE_PATH") which has uncommitted changes. Commit and push before moving on."
exit 0
