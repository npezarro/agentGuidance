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
PEER_COMMITS=""
declare -A CHECKED_REPOS 2>/dev/null || true

# Ledger format is <repo_root>\t<file_path>\t<epoch>. The epoch is read into its own
# variable and ignored here: without it, the trailing field would be appended to
# file_path (read gives the remainder of the line to the last variable) and every
# realpath would miss.
while IFS=$'\t' read -r repo_root file_path _epoch; do
  # `.git` is a DIRECTORY in a normal checkout but a FILE (`gitdir: ...`) in a linked
  # worktree, so a -d test silently skips every per-session worktree
  # (guidance/concurrent-sessions.md) and the gate never sees that work at all.
  [ -e "$repo_root/.git" ] || continue
  repo_name=$(basename "$repo_root")
  # Label a worktree by its PROJECT, not by the worktree directory name: "probe (1)"
  # tells you nothing about which repo has stranded work. Checks still run against the
  # worktree itself — only the display name is resolved through the common git dir.
  if [ -f "$repo_root/.git" ]; then
    _common=$(cd "$repo_root" && git rev-parse --git-common-dir 2>/dev/null || echo "")
    case "$_common" in
      */.git) repo_name="$(basename "$(dirname "$_common")") (worktree ${repo_name})" ;;
    esac
  fi

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

  # Check unpushed commits per repo (only once per repo).
  #
  # Per COMMIT, not per repo. The gate used to count `@{u}..HEAD` for the whole repo, so
  # touching one file made this session responsible for every unpushed commit in it,
  # including a live peer's. That fired on 2026-08-01: a session was told to push a
  # two-minute-old commit written by a different session. A commit counts as this
  # session's only if it contains a file this session actually wrote (Edit/Write ledger
  # only; the Bash-inferred ledger is heuristic and must not reach a blocking gate).
  if [ -z "${CHECKED_REPOS[$repo_root]+x}" ] 2>/dev/null; then
    CHECKED_REPOS[$repo_root]=1
    # A branch with no upstream is NOT automatically safe. A per-session git worktree
    # (guidance/concurrent-sessions.md) starts on a fresh local branch, so `@{u}` fails
    # and the old code skipped the unpushed check entirely — a session could commit in a
    # worktree, never merge, and stop with the gate completely silent. Verified
    # 2026-08-02: empty output, exit 0, on a committed-but-unmerged file.
    #
    # For those branches the right question is not "pushed to my upstream" but "does
    # this work exist anywhere on the remote yet", so compare against the remote's
    # default branch instead.
    upstream=$(cd "$repo_root" && git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "")
    RANGE=""
    if [ -n "$upstream" ]; then
      RANGE='@{u}..HEAD'
    else
      base=$(cd "$repo_root" && git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo "")
      if [ -z "$base" ]; then
        for cand in origin/main origin/master; do
          if (cd "$repo_root" && git rev-parse --verify -q "$cand" >/dev/null 2>&1); then base="$cand"; break; fi
        done
      fi
      # No remote at all (or a detached HEAD with no base): nothing to compare against,
      # so stay silent rather than invent a range.
      [ -n "$base" ] && RANGE="${base}..HEAD"
    fi
    if [ -n "$RANGE" ]; then
      MY_PATHS=$(awk -F'\t' -v r="$repo_root" '$1 == r { print $2 }' "$TRACK_FILE" 2>/dev/null \
        | while IFS= read -r p; do realpath --relative-to="$repo_root" "$p" 2>/dev/null; done | sort -u)
      mine=0; theirs=0
      while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        files=$(cd "$repo_root" && git show --name-only --format= "$sha" 2>/dev/null)
        if [ -n "$MY_PATHS" ] && printf '%s\n' "$files" | grep -qxF -f <(printf '%s\n' "$MY_PATHS") 2>/dev/null; then
          mine=$((mine + 1))
        else
          theirs=$((theirs + 1))
        fi
      done <<< "$(cd "$repo_root" && git rev-list "$RANGE" 2>/dev/null)"
      [ "$mine" -gt 0 ] && UNPUSHED_REPOS="${UNPUSHED_REPOS}${repo_name} (${mine}), "
      [ "$theirs" -gt 0 ] && PEER_COMMITS="${PEER_COMMITS}${repo_name} (${theirs}), "
    fi
  fi
done < "$TRACK_FILE"

MSG=""
[ -n "$DIRTY_FILES" ] && MSG="Uncommitted files: ${DIRTY_FILES%, }. "
[ -n "$UNPUSHED_REPOS" ] && MSG="${MSG}Unpushed commits: ${UNPUSHED_REPOS%, }. "

NOTE=""
[ -n "$PEER_COMMITS" ] && NOTE="Not blocking on another session's unpushed commits: ${PEER_COMMITS%, }. If they are stranded, push to THEIR branch rather than resetting; see guidance/concurrent-sessions.md. "

ACK_NOTE=""
[ -n "$ACKED_FILES" ] && ACK_NOTE="Acknowledged as not-this-session work: ${ACKED_FILES%, }. "

if [ -n "$MSG" ]; then
  printf '{"decision":"block","reason":"GIT-PUSH GATE: %s%sCommit and push before stopping."}\n' "$MSG" "$NOTE"
elif [ -n "$ACK_NOTE" ] || [ -n "$NOTE" ]; then
  # Nothing blocking, but keep the acknowledged paths and peer commits visible rather than silent.
  printf '{"systemMessage":"GIT-PUSH GATE: passed. %s%s"}\n' "$ACK_NOTE" "$NOTE"
fi

exit 0
