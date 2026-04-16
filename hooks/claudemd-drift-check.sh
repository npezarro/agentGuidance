#!/usr/bin/env bash
# claudemd-drift-check.sh — PostToolUse hook for Bash
# Detects when git commit happens but CLAUDE.md wasn't included in the staged changes.
# Warns (doesn't block) when new exports, routes, or commands are committed without doc updates.

set -euo pipefail

INPUT=$(cat)

# Only trigger on git commit commands
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE "git commit" || exit 0

# Don't trigger on amend or merge commits
echo "$COMMAND" | grep -qE "\-\-amend|merge" && exit 0

# Get the repo root from the tool's working directory
STDOUT=$(echo "$INPUT" | jq -r '.stdout // empty' 2>/dev/null)
# Check if CLAUDE.md was in the commit
if echo "$STDOUT" | grep -q "CLAUDE.md"; then
  # CLAUDE.md was updated — no drift
  exit 0
fi

# Check what files were just committed by looking at staged diff indicators in output
# Look for signs of new functionality: new exports, routes, API endpoints, commands
HAS_NEW_FUNCTIONALITY=false

# Get the repo we're in by checking the commit output for branch info
REPO_DIR=""
for candidate in "$PWD" "$HOME/repos/"*; do
  [ -d "$candidate/.git" ] || continue
  # Check if the most recent commit is within the last 10 seconds
  LAST_COMMIT_AGE=$(cd "$candidate" && git log -1 --format="%cr" 2>/dev/null || echo "old")
  if echo "$LAST_COMMIT_AGE" | grep -qE "seconds? ago"; then
    REPO_DIR="$candidate"
    break
  fi
done

[ -z "$REPO_DIR" ] && exit 0
[ -f "$REPO_DIR/CLAUDE.md" ] || exit 0

# Check the last commit's diff for documentation-worthy changes
DIFF=$(cd "$REPO_DIR" && git diff HEAD~1..HEAD --unified=0 2>/dev/null || echo "")
[ -z "$DIFF" ] && exit 0

# Detect patterns that usually need CLAUDE.md updates
TRIGGERS=""
echo "$DIFF" | grep -qE "^\+.*export (default |async )?function" && TRIGGERS="${TRIGGERS}new exports, "
echo "$DIFF" | grep -qE "^\+.*app\.(get|post|put|delete|patch)\(" && TRIGGERS="${TRIGGERS}new routes, "
echo "$DIFF" | grep -qE "^\+.*router\.(get|post|put|delete|patch)\(" && TRIGGERS="${TRIGGERS}new routes, "
echo "$DIFF" | grep -qE "^\+.*\"(scripts|bin)\":" && TRIGGERS="${TRIGGERS}new commands, "
echo "$DIFF" | grep -qE "^\+.*(NEXT_PUBLIC_|VITE_|REACT_APP_)" && TRIGGERS="${TRIGGERS}new env vars, "
echo "$DIFF" | grep -qE "^\+.*createServer|listen\(" && TRIGGERS="${TRIGGERS}new server setup, "

if [ -n "$TRIGGERS" ]; then
  TRIGGERS="${TRIGGERS%, }"  # trim trailing comma
  echo "CLAUDE.md drift warning: This commit added ${TRIGGERS} but CLAUDE.md was not updated. Consider updating CLAUDE.md to document new functionality."
fi

exit 0
