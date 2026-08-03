#!/usr/bin/env bash
# score-session.sh — Stop hook that scores the interactive session.
# Uses the shared stop-hook-guard library for recursion prevention.
# Runs fire-and-forget so it doesn't block session exit.

source "$(dirname "$0")/lib/stop-hook-guard.sh"
stop_hook_init "score-session" --invokes-claude

# Private tree is canonical: it has the usage gate + CLAUDE_CODE_* env-strip,
# and its scores/ dir is the one tier-2 actually reads (Fable 5 review item 4)
SCORER="$HOME/repos/autonomousDev-private/supervisor/score.sh"
[ -x "$SCORER" ] || exit 0

# Content fingerprint fallback (env var guard is handled by stop_hook_init)
LAST_MSG=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty')
if printf '%s' "$LAST_MSG" | grep -q 'Session Scorer\|scoring a completed agent interaction'; then
  exit 0
fi

# --- Don't score headless runs: their runner already does it, correctly ---
# Stop hooks fire on `claude -p` too (KB patterns/sessionstart-hook-conditional-
# injection.md). autonomousDev-private's run.sh, learnings-pass/run.sh and
# fix-checker/run.sh each call supervisor/score.sh themselves with the right
# --agent-type and the FULL run log. This hook firing on the same session added a
# second, worse score labelled "interactive" -- which is why 68% of the corpus was
# tagged interactive and the supervisor's per-profile table was meaningless.
AGENT_TYPE="unknown"
pid="$PPID"; CMDLINE=""
for _ in 1 2 3 4 5 6; do
  [ -r "/proc/$pid/cmdline" ] || break
  c="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "")"
  # Match argv[0]'s basename, NOT "claude appears somewhere in the cmdline".
  # Bash-tool commands run as `/bin/bash -c <script text>`, and that script text
  # is part of the cmdline -- so a substring match happily identifies a wrapper
  # shell as "the claude process" whenever the command being run merely mentions
  # claude or -p. (Caught doing exactly that while testing this hook.)
  exe="${c%% *}"
  case "${exe##*/}" in
    claude|claude.exe) CMDLINE="$c"; break ;;
  esac
  pid="$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null || echo)"
  { [ -z "$pid" ] || [ "$pid" = 0 ]; } && break
done
if [ -n "$CMDLINE" ]; then
  # Headless: the runner owns scoring this session. Bail.
  printf '%s' " $CMDLINE " | grep -qE ' (-p|--print)([ =]|$)' && exit 0
  AGENT_TYPE="interactive"
fi
# If the invocation couldn't be read, fall through as "unknown" rather than
# asserting "interactive". A wrong label is worse than an honest one: it silently
# poisons the trend data, which is exactly the failure being fixed here.

# --- Prefer the actual tool-call record over the agent's self-report ---
# last_assistant_message is a SUMMARY of the work. Rules like
# verify_before_asserting and test_before_reporting can only be judged from what
# actually ran, so build a digest from the transcript and fall back to the
# summary only if that isn't possible.
TMPFILE=$(mktemp /tmp/session-score-XXXXXX.txt)
DIGEST_TOOL="$(dirname "$0")/lib/transcript-digest.py"

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ -f "$DIGEST_TOOL" ] \
   && python3 "$DIGEST_TOOL" "$TRANSCRIPT" 12000 > "$TMPFILE" 2>/dev/null \
   && [ -s "$TMPFILE" ]; then
  :
else
  printf '%s' "$LAST_MSG" | tail -c 5000 > "$TMPFILE"
fi

# Skip trivial sessions
if [ "$(wc -c < "$TMPFILE")" -lt 200 ]; then
  rm -f "$TMPFILE"
  exit 0
fi

(
  "$SCORER" --agent-type "$AGENT_TYPE" --session-data "$TMPFILE" 2>/dev/null
  rm -f "$TMPFILE"
) &

exit 0
