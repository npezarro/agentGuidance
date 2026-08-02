#!/usr/bin/env bash
# test-worktree-guard.sh — payload tests for the PreToolUse worktree guard.
#
#   bash hooks/tests/test-worktree-guard.sh      # exit 0 = all pass
#
# The guard must fire ONLY on a real collision: a write to a ~/repos repo, outside a
# worktree, while a LIVE peer holds that repo. Everything else must pass through
# untouched, because this runs on every single Edit/Write and a guard that fires on safe
# work trains reflexive acks.
#
# Calling convention: JSON payload on stdin, `.tool_input.file_path`. Piping anything else
# makes jq return empty and the hook exits 0, which is indistinguishable from "allowed".
set -uo pipefail

HOOKS="${GUARD_HOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOK="$HOOKS/worktree-guard.sh"
PEER="wtguard-peer-$$"
MYSID="wtguard-me-$$"
# An ISOLATED fixture repo, not a real ~/repos checkout. Two constraints collide here:
# write-target-inference ignores /tmp/*, so the fixture cannot live there; and a real
# checkout has genuinely live sessions holding its ledgers, so the fixture could not
# control the peer set (first run: four cases "failed" and the hook was right every time).
# ~/.cache satisfies both, via WORKTREE_GUARD_ROOT.
FIXTURE="$HOME/.cache/wtguard-test-$$"
REPO="$FIXTURE/myrepo"
export WORKTREE_GUARD_ROOT="$HOME/.cache"
mkdir -p "$REPO/node_modules"
git init -q "$REPO"
printf 'node_modules/\n' > "$REPO/.gitignore"
: > "$REPO/agent.md"
: > "$REPO/node_modules/x.js"
OTHER="$HOME/.cache/wtguard-other-$$"
mkdir -p "$OTHER/otherrepo" && git init -q "$OTHER/otherrepo"
PASS=0; FAIL=0

cleanup() {
  rm -f "/tmp/claude-session-alive-$PEER" "/tmp/claude-repos-touched-$PEER" \
        "/tmp/claude-claim-ack-$MYSID"
  rm -rf "$FIXTURE" "$OTHER"
}
trap cleanup EXIT

ok()  { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s (%s)\n' "$1" "$2"; }

# $1 = expect deny|allow, $2 = label, $3 = file_path
try() {
  jq -nc --arg s "$MYSID" --arg fp "$3" \
    '{session_id:$s, tool_name:"Edit", cwd:"/tmp", tool_input:{file_path:$fp}}' \
    | bash "$HOOK" >/dev/null 2>&1
  local rc=$? got="allow"
  [ "$rc" = 2 ] && got="deny"
  [ "$got" = "$1" ] && ok "$2" || bad "$2" "expected $1, got $got (exit $rc)"
}

# --- a LIVE peer holding the repo -------------------------------------------------
touch "/tmp/claude-session-alive-$PEER"
printf '%s\t%s\t%s\n' "$REPO" "$REPO/agent.md" "$(date +%s)" > "/tmp/claude-repos-touched-$PEER"

echo "fires only on a real collision"
try deny  "shared checkout + live peer"        "$REPO/agent.md"
try allow "same repo, but inside a worktree"   "$REPO/.claude/worktrees/foo/agent.md"
try allow "outside ~/repos"                    "/etc/hosts"
try allow "different repo, peer holds another" "$OTHER/otherrepo/f.md"
try allow "gitignored path in the repo"        "$REPO/node_modules/x.js"

echo "escape hatch"
printf '%s\t%s\n' "myrepo" "ops work, one-file edit" > "/tmp/claude-claim-ack-$MYSID"
try allow "acknowledged repo passes"           "$REPO/agent.md"
rm -f "/tmp/claude-claim-ack-$MYSID"
printf '%s\t%s\n' "myrepo" "" > "/tmp/claude-claim-ack-$MYSID"
try deny  "ack with an EMPTY reason is not an ack" "$REPO/agent.md"
rm -f "/tmp/claude-claim-ack-$MYSID"

echo "peer liveness"
# Stale marker: sessions exit without cleaning up, and markers accumulate. A guard that
# treats a dead session as live blocks work forever.
touch -d '2 hours ago' "/tmp/claude-session-alive-$PEER"
try allow "peer marker is STALE (>30m)"        "$REPO/agent.md"
touch "/tmp/claude-session-alive-$PEER"

rm -f "/tmp/claude-session-alive-$PEER"
try allow "peer has no liveness marker at all" "$REPO/agent.md"
touch "/tmp/claude-session-alive-$PEER"

rm -f "/tmp/claude-repos-touched-$PEER"
try allow "no peer holds this repo"            "$REPO/agent.md"

echo "malformed payloads must never block"
printf '%s' '{"session_id":"x","tool_name":"Edit","tool_input":{}}' | bash "$HOOK" >/dev/null 2>&1
[ $? = 0 ] && ok "missing file_path" || bad "missing file_path" "blocked"
printf '%s' 'not json at all' | bash "$HOOK" >/dev/null 2>&1
[ $? = 0 ] && ok "non-JSON stdin" || bad "non-JSON stdin" "blocked"
printf '%s' '' | bash "$HOOK" >/dev/null 2>&1
[ $? = 0 ] && ok "empty stdin" || bad "empty stdin" "blocked"

echo
printf 'passed %s, failed %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
