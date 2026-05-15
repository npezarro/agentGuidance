#!/usr/bin/env bash
# score-session.sh — Stop hook that scores the interactive session.
# Uses the shared stop-hook-guard library for recursion prevention.
# Runs fire-and-forget so it doesn't block session exit.

source "$(dirname "$0")/lib/stop-hook-guard.sh"
stop_hook_init "score-session" --invokes-claude

SCORER="$HOME/repos/autonomousDev/supervisor/score.sh"
[ -x "$SCORER" ] || exit 0

# Content fingerprint fallback (env var guard is handled by stop_hook_init)
LAST_MSG=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty')
if printf '%s' "$LAST_MSG" | grep -q 'Session Scorer\|scoring a completed agent interaction'; then
  exit 0
fi

# Extract a useful summary: last 5000 chars (most relevant to final state)
SUMMARY=$(printf '%s' "$LAST_MSG" | tail -c 5000)

# Skip trivial sessions
[ "${#SUMMARY}" -lt 200 ] && exit 0

# Write to temp file and run scorer in background
TMPFILE=$(mktemp /tmp/session-score-XXXXXX.txt)
printf '%s' "$SUMMARY" > "$TMPFILE"

(
  "$SCORER" --agent-type interactive --session-data "$TMPFILE" 2>/dev/null
  rm -f "$TMPFILE"
) &

exit 0
