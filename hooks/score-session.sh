#!/usr/bin/env bash
# score-session.sh — Stop hook that scores the interactive session.
# Receives conversation transcript on stdin, extracts key content,
# and runs the ecosystem supervisor scorer in the background.
#
# Runs fire-and-forget so it doesn't block session exit.

set -uo pipefail

SCORER="$HOME/repos/autonomousDev/supervisor/score.sh"
[ -x "$SCORER" ] || exit 0

# Prevent infinite recursion: scorer sessions trigger Stop hooks too,
# which would invoke this script again, creating an endless chain.
# Detect scorer conversations and bail out.
[ "${CLAUDE_SCORER_ACTIVE:-}" = "1" ] && exit 0

# Read conversation from stdin (piped by the stop hook framework)
CONVERSATION=$(cat)

# Skip if conversation contains the scorer prompt (recursive call detection)
if printf '%s' "$CONVERSATION" | grep -q 'Session Scorer\|scoring a completed agent interaction'; then
  exit 0
fi

# Extract a useful summary: last 5000 chars (most relevant to final state)
SUMMARY=$(printf '%s' "$CONVERSATION" | tail -c 5000)

# Skip if conversation is too short (quick Q&A, not a real session)
[ "${#SUMMARY}" -lt 200 ] && exit 0

# Write to temp file and run scorer in background
TMPFILE=$(mktemp /tmp/session-score-XXXXXX.txt)
printf '%s' "$SUMMARY" > "$TMPFILE"

# Fire and forget: scorer runs after session exits
(
  "$SCORER" --agent-type interactive --session-data "$TMPFILE" 2>/dev/null
  rm -f "$TMPFILE"
) &

exit 0
