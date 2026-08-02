#!/usr/bin/env bash
# test-guards.sh — regression tests for the two cross-session guards.
#
# Run before touching claim-guard.sh or check-unpushed.sh:
#   bash hooks/tests/test-guards.sh
#
# Both guards failed in ways that were invisible until someone hit them in anger
# (2026-08-01): claim-guard denied a SAFE command because the commit message
# described the dangerous one, and check-unpushed blamed a session for a peer's
# unpushed commit. Both fixes are subtle (command-segment parsing; commit-to-ledger
# intersection) and neither had a test. These are the cases that mattered.
#
# NOTE ON CALLING CONVENTION, the thing that wasted the most time: these hooks read a
# JSON PAYLOAD on stdin, not a raw command string. Piping a bare command makes
# `jq -r '.session_id'` return empty and the hook exits 0 — which looks exactly like
# "allowed" and will happily confirm a fix that is not there.
set -uo pipefail

# Overridable so the suite can be pointed at an older copy of the hooks as a negative
# control. A test that has never been seen to FAIL proves nothing; see the header of
# hooks/tests/README.md for the one-liner that runs it against the pre-fix versions.
HOOKS="${GUARD_HOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PEER="guardtest-peer-$$"
MYSID="guardtest-me-$$"
TMPREPO=$(mktemp -d)
PASS=0; FAIL=0

cleanup() {
  rm -f "/tmp/claude-session-alive-$PEER" "/tmp/claude-repos-claimed-$PEER" \
        "/tmp/claude-repos-touched-$MYSID" "/tmp/claude-claim-noted-$MYSID"
  rm -rf "$TMPREPO"
}
trap cleanup EXIT

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s (%s)\n' "$1" "$2"; }

# ---------------------------------------------------------------- claim-guard
# A live peer must hold a repo, or the guard correctly has nothing to guard. The repo
# must be under $HOME (write-target-inference ignores /tmp/* by design), so this uses
# agentGuidance itself as the contested repo. No git command is ever run against it:
# the guard only inspects the command STRING.
GUARD_REPO="$HOME/repos/agentGuidance"
touch "/tmp/claude-session-alive-$PEER"
printf '%s\t%s\t%s\n' "$GUARD_REPO" "$GUARD_REPO/agent.md" "$(date +%s)" > "/tmp/claude-repos-claimed-$PEER"

guard() {  # $1 = expect deny|allow, $2 = label, $3 = command
  rm -f "/tmp/claude-claim-noted-$MYSID"
  jq -nc --arg c "$3" --arg cwd "$GUARD_REPO" --arg s "$MYSID" \
    '{session_id:$s, tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}' \
    | bash "$HOOKS/claim-guard.sh" deny >/dev/null 2>&1
  local rc=$?
  local got="allow"; [ "$rc" = 2 ] && got="deny"
  [ "$got" = "$1" ] && ok "$2" || bad "$2" "expected $1, got $got (exit $rc)"
}

echo "claim-guard: must DENY blast-radius commands while a peer holds the repo"
guard deny  "git add -A"                'git add -A'
guard deny  "git add ."                 'git add .'
guard deny  "git commit -am"            'git commit -am "x"'

echo "claim-guard: must ALLOW safe commands (regression: message described the hazard)"
guard allow "explicit path + msg naming git add -A" \
      'git add guidance/x.md && git commit -q -m "records a git add -A failure"'
guard allow "heredoc body naming the hazard" \
      "git add a.md && git commit -F - <<'MSG'
mentions git add -A in the body
MSG"
guard allow "plain explicit path"       'git add .gitignore'
guard allow "read-only"                 'git status --short'

# ------------------------------------------------------------- check-unpushed
cd "$TMPREPO" || exit 1
git init -q --bare origin.git
git clone -q origin.git work 2>/dev/null
cd work || exit 1
git config user.email t@t; git config user.name t
echo base > base.txt; git add base.txt; git commit -qm base
git push -q origin HEAD 2>/dev/null
echo peer > peer.txt; git add peer.txt; git commit -qm "peer session work"
echo mine > mine.txt; git add mine.txt; git commit -qm "my work"

gate() { jq -nc --arg s "$MYSID" '{session_id:$s}' | bash "$HOOKS/check-unpushed.sh" 2>/dev/null; }

echo "check-unpushed: must be per-COMMIT, not per-repo"
printf '%s\t%s\n' "$PWD" "$PWD/base.txt" > "/tmp/claude-repos-touched-$MYSID"
out=$(gate); dec=$(printf '%s' "$out" | jq -r '.decision // "none"' 2>/dev/null)
[ "$dec" = "none" ] && ok "no block when every unpushed commit is a peer's" \
                    || bad "no block when every unpushed commit is a peer's" "decision=$dec"

printf '%s\t%s\n' "$PWD" "$PWD/mine.txt" > "/tmp/claude-repos-touched-$MYSID"
out=$(gate); dec=$(printf '%s' "$out" | jq -r '.decision // "none"' 2>/dev/null)
[ "$dec" = "block" ] && ok "blocks when an unpushed commit contains this session's file" \
                     || bad "blocks when an unpushed commit contains this session's file" "decision=$dec"
printf '%s' "$out" | grep -q "Not blocking on another session" \
  && ok "names the peer's commits without blocking on them" \
  || bad "names the peer's commits without blocking on them" "note missing"

echo
printf 'passed %s, failed %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
