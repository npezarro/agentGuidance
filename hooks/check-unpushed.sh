#!/usr/bin/env bash
# Stop hook: blocks if any FILE written this session is still uncommitted or unpushed.
# Reads /tmp/claude-repos-touched-{session_id} (populated by track-repo-writes PostToolUse hook).
# Only checks the specific files written, not all repo state (avoids false positives from
# pre-existing untracked files).
#
# Acknowledgements (2026-07-30): the gate equates "a file this session wrote is dirty" with
# "this session has unpushed work". That is false when the session wrote a file and then
# deliberately reverted it -- e.g. it moved its work into a git worktree, or a CONCURRENT
# agent session left its own uncommitted edits on the same path. ~/repos/<app> is one working
# tree that several sessions can edit at once, so "dirty" does not imply "mine".
#
# A session may acknowledge a specific path by appending a TAB-separated line to
#   /tmp/claude-repos-ack-{session_id}
#   <repo_name>/<rel_path>\t<reason>
# An acknowledged path is reported but does NOT block. Every ack is appended to
# ~/.claude/logs/git-push-gate-acks.log so the decision stays auditable -- this is a
# "prove it and record it" escape hatch, not a mute switch. Blanket acks are impossible:
# each line must name one exact path and carry a reason.
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

TRACK_FILE="/tmp/claude-repos-touched-${SESSION_ID}"
[ -f "$TRACK_FILE" ] || exit 0

ACK_FILE="/tmp/claude-repos-ack-${SESSION_ID}"
ACK_LOG="$HOME/.claude/logs/git-push-gate-acks.log"

# Returns 0 and echoes the reason when $1 is an acknowledged path.
ack_reason_for() {
  [ -f "$ACK_FILE" ] || return 1
  awk -F'\t' -v target="$1" '$1 == target && $2 != "" { print $2; found=1; exit } END { exit !found }' \
    "$ACK_FILE" 2>/dev/null
}

DIRTY_FILES=""
ACKED_FILES=""
UNPUSHED_REPOS=""
declare -A CHECKED_REPOS 2>/dev/null || true

while IFS=$'\t' read -r repo_root file_path; do
  [ -d "$repo_root/.git" ] || continue
  repo_name=$(basename "$repo_root")

  # Check if this specific file has uncommitted changes
  rel_path=$(realpath --relative-to="$repo_root" "$file_path" 2>/dev/null || basename "$file_path")
  status=$(cd "$repo_root" && git status --porcelain -- "$rel_path" 2>/dev/null || true)
  if [ -n "$status" ]; then
    key="${repo_name}/${rel_path}"
    if reason=$(ack_reason_for "$key"); then
      case "$ACKED_FILES" in
        *"$key"*) ;;
        *)
          ACKED_FILES="${ACKED_FILES}${key} (${reason}), "
          mkdir -p "$(dirname "$ACK_LOG")" 2>/dev/null || true
          printf '%s\t%s\t%s\t%s\n' \
            "$(date -Iseconds)" "$SESSION_ID" "$key" "$reason" >> "$ACK_LOG" 2>/dev/null || true
          ;;
      esac
    else
      DIRTY_FILES="${DIRTY_FILES}${key}, "
    fi
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
elif [ -n "$ACKED_FILES" ]; then
  # Nothing blocking, but keep the acknowledged paths visible rather than silent.
  printf '{"systemMessage":"GIT-PUSH GATE: passed. Acknowledged as not-this-session'"'"'s work: %s"}\n' \
    "${ACKED_FILES%, }"
fi

exit 0
