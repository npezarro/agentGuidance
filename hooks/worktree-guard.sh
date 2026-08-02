#!/usr/bin/env bash
# worktree-guard.sh — PreToolUse (Edit|Write). Enforces per-session git worktrees at the
# only moment enforcement can still help: the FIRST write to a contested repo.
#
# Why not a Stop hook (asked 2026-08-02): by Stop time the editing already happened in the
# shared checkout, so blocking the stop cannot retroactively isolate anything — there is no
# remediation left, only nagging. Worse, Stop cannot distinguish "correctly skipped a
# worktree" (read-only work, ops, one-file edits, all explicitly exempt in agent.md) from
# "forgot", so it would fire on both and train reflexive acks, which is how a guard stops
# working. Stop already has its correct job here: check-unpushed.sh catches work STRANDED
# in a worktree, i.e. "did your work escape this machine", not "did you use the workflow".
#
# Fires ONLY when all three hold, which is what makes this enforcement and not friction:
#   1. the target file resolves inside a repo under ~/repos, AND
#   2. it is not already inside .claude/worktrees/, AND
#   3. another LIVE session holds that same repo.
# A solo session in a repo nobody else is touching never sees this hook.
#
# Blocks with exit 2 + stderr (PreToolUse: stdout on exit 0 does not reliably reach the
# model). Escape hatch, because a denial must never be a dead end:
#   printf '%s\t%s\n' '<repo-name>' '<reason>' >> /tmp/claude-claim-ack-<sid>
# Shares that ack file and the audit log with claim-guard.sh so there is one override
# mechanism and one trail, not two.
set -uo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0

FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FP" ] && exit 0

# ---------------------------------------------------------------- cheap exits first
# This runs on EVERY Edit/Write, so the ordering here is deliberate: the two string tests
# below cost nothing and cover the overwhelming majority of calls, and the expensive
# ledger scan only runs for a repo write that is actually outside a worktree.

# Already isolated. Keyed on the TARGET PATH, not cwd: editing an absolute canonical path
# from inside a worktree is still unisolated, and cwd would call that safe.
case "$FP" in
  */.claude/worktrees/*) exit 0 ;;
esac

# Overridable so a test can point at an isolated fixture. Without this the suite has to
# use a real ~/repos checkout, where genuinely live sessions hold the ledgers and the
# fixture cannot control the peer set — four cases "failed" that way on first run, and the
# hook was correct every time.
GUARD_ROOT="${WORKTREE_GUARD_ROOT:-$HOME/repos}"
case "$FP" in
  "$GUARD_ROOT"/*) ;;
  *) exit 0 ;;                 # outside the guarded root: not what this guards
esac

NOW=$(date +%s)
LIVE_WINDOW="${CLAIM_GUARD_LIVE_WINDOW:-1800}"
TOUCH_WINDOW="${CLAIM_GUARD_TOUCH_WINDOW:-7200}"
ACK="/tmp/claude-claim-ack-${SID}"
LOG="$HOME/.claude/logs/claim-guard.log"

LIB="$HOME/repos/agentGuidance/hooks/lib/write-target-inference.sh"
[ -f "$LIB" ] || exit 0
# shellcheck source=lib/write-target-inference.sh
. "$LIB"

REPO=$(wti_repo_root "$FP")
[ -z "$REPO" ] && exit 0        # not a repo file, or gitignored
REPO_NAME=$(basename "$REPO")

log_event() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$SID" "$1" "$2" >> "$LOG" 2>/dev/null
}

# Acknowledged: report nothing further, but leave a trail. Same file and format as
# claim-guard so one override covers both guards for that repo.
if [ -f "$ACK" ] && awk -F'\t' -v t="$REPO_NAME" '$1 == t && $2 != "" { found=1 } END { exit !found }' "$ACK" 2>/dev/null; then
  log_event "worktree-ack" "$REPO_NAME"
  exit 0
fi

session_is_live() {
  local f="/tmp/claude-session-alive-$1" m
  [ -f "$f" ] || return 1
  m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  [ $(( NOW - m )) -le "$LIVE_WINDOW" ]
}

# A subagent runs under its own session id but is MY work, not a competing writer.
is_my_subagent() {
  local other="$1" hit
  hit=$(find "$HOME/.claude/projects" -maxdepth 4 -path "*/${SID}/subagents/*${other}*" -print -quit 2>/dev/null)
  [ -n "$hit" ]
}

# Is another live session holding this repo? Both ledgers count here: the Bash-inferred
# one is heuristic, but this hook only DELAYS a write behind a worktree it should have
# taken anyway, so a rare false positive costs one EnterWorktree call rather than lost
# work. (Contrast check-unpushed, which blocks a session's exit and therefore reads the
# authorship ledger only.)
PEER_SID=""; PEER_AGE=""
for f in /tmp/claude-repos-touched-* /tmp/claude-repos-claimed-*; do
  [ -f "$f" ] || continue
  m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  [ $(( NOW - m )) -le "$TOUCH_WINDOW" ] || continue
  b=$(basename "$f"); sid="${b#claude-repos-touched-}"; sid="${sid#claude-repos-claimed-}"
  [ "$sid" = "$SID" ] && continue
  session_is_live "$sid" || continue
  is_my_subagent "$sid" && continue
  if awk -F'\t' -v r="$REPO" '$1 == r { found=1 } END { exit !found }' "$f" 2>/dev/null; then
    PEER_SID="$sid"; PEER_AGE=$(( (NOW - m + 30) / 60 )); break
  fi
done
[ -z "$PEER_SID" ] && exit 0     # nobody else here: no isolation needed, no friction

log_event "worktree-deny" "$REPO_NAME (peer ${PEER_SID:0:8})"
cat >&2 <<EOF
WORKTREE GUARD: '${REPO_NAME}' is being written by another LIVE session (${PEER_SID:0:8}, active ${PEER_AGE}m ago) and you are editing the shared checkout.

Take a worktree first, then redo this edit:
  EnterWorktree            -> creates .claude/worktrees/<name> on its own branch
  ... work, commit ...
  merge to the default branch and push before you stop

Why: one checkout, several sessions. In a worktree a stage-everything commit is safe by
construction instead of merely guarded. See guidance/concurrent-sessions.md.

Deploys read the CANONICAL checkout, so merge and push before deploying from a worktree.

If a worktree is genuinely wrong here (ops work, a one-file edit, read-only), record the
decision and retry:
  printf '%s\t%s\n' '${REPO_NAME}' '<reason>' >> ${ACK}
EOF
exit 2
