#!/usr/bin/env bash
# Stop hook: blocks if any FILE written this session is still uncommitted or unpushed.
# Reads /tmp/claude-repos-touched-{session_id} (populated by track-repo-writes PostToolUse hook).
# Only checks the specific files written, not all repo state (avoids false positives from
# pre-existing untracked files).
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

TRACK_FILE="/tmp/claude-repos-touched-${SESSION_ID}"
[ -f "$TRACK_FILE" ] || exit 0

DIRTY_FILES=""
UNPUSHED_REPOS=""
declare -A CHECKED_REPOS 2>/dev/null || true

while IFS=$'\t' read -r repo_root file_path; do
  [ -d "$repo_root/.git" ] || continue
  repo_name=$(basename "$repo_root")

  # Check if this specific file has uncommitted changes
  rel_path=$(realpath --relative-to="$repo_root" "$file_path" 2>/dev/null || basename "$file_path")
  status=$(cd "$repo_root" && git status --porcelain -- "$rel_path" 2>/dev/null || true)
  if [ -n "$status" ]; then
    DIRTY_FILES="${DIRTY_FILES}${repo_name}/${rel_path}, "
  fi

  # Check unpushed commits per repo (only once per repo)
  if [ -z "${CHECKED_REPOS[$repo_root]+x}" ] 2>/dev/null; then
    CHECKED_REPOS[$repo_root]=1
    upstream=$(cd "$repo_root" && git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "")
    if [ -n "$upstream" ]; then
      ahead=$(cd "$repo_root" && git rev-list '@{u}'..HEAD --count 2>/dev/null || echo "0")
      if [ "$ahead" -gt 0 ]; then
        UNPUSHED_REPOS="${UNPUSHED_REPOS}${repo_name} (${ahead}), "
      fi
    fi
  fi
done < "$TRACK_FILE"

MSG=""
[ -n "$DIRTY_FILES" ] && MSG="Uncommitted files: ${DIRTY_FILES%, }. "
[ -n "$UNPUSHED_REPOS" ] && MSG="${MSG}Unpushed commits: ${UNPUSHED_REPOS%, }. "

if [ -n "$MSG" ]; then
  printf '{"decision":"block","reason":"GIT-PUSH GATE: %sCommit and push before stopping."}\n' "$MSG"
fi

exit 0
