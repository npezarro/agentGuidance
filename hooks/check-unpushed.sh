#!/usr/bin/env bash
# Stop hook: blocks if any repo TOUCHED THIS SESSION has uncommitted or unpushed changes.
# Reads /tmp/claude-repos-touched-{session_id} (populated by track-repo-writes PostToolUse hook).
# Outputs blocking JSON if dirty repos found, exits silently if all clean.
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

TRACK_FILE="/tmp/claude-repos-touched-${SESSION_ID}"
[ -f "$TRACK_FILE" ] || exit 0

DIRTY=""
UNPUSHED=""

# De-duplicate repo list
REPOS=$(sort -u "$TRACK_FILE")

while IFS= read -r dir; do
  [ -d "$dir/.git" ] || continue
  repo_name=$(basename "$dir")

  # Check uncommitted changes (staged + unstaged tracked files)
  changes=$(cd "$dir" && git diff --name-only HEAD 2>/dev/null || true)
  staged=$(cd "$dir" && git diff --cached --name-only 2>/dev/null || true)
  # Also check for new untracked files that aren't gitignored
  untracked=$(cd "$dir" && git ls-files --others --exclude-standard 2>/dev/null || true)
  if [ -n "$changes" ] || [ -n "$staged" ] || [ -n "$untracked" ]; then
    DIRTY="${DIRTY}${repo_name}, "
  fi

  # Check unpushed commits
  upstream=$(cd "$dir" && git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "")
  if [ -n "$upstream" ]; then
    ahead=$(cd "$dir" && git rev-list '@{u}'..HEAD --count 2>/dev/null || echo "0")
    if [ "$ahead" -gt 0 ]; then
      UNPUSHED="${UNPUSHED}${repo_name} (${ahead}), "
    fi
  fi
done <<< "$REPOS"

MSG=""
[ -n "$DIRTY" ] && MSG="Uncommitted changes: ${DIRTY%, }. "
[ -n "$UNPUSHED" ] && MSG="${MSG}Unpushed commits: ${UNPUSHED%, }. "

if [ -n "$MSG" ]; then
  printf '{"decision":"block","reason":"GIT-PUSH GATE: %sCommit and push before stopping."}\n' "$MSG"
fi

exit 0
