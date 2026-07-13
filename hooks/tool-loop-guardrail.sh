#!/usr/bin/env bash
# tool-loop-guardrail.sh — PostToolUse hook that detects repeated identical tool calls.
# Programmatic enforcement of ESSENTIAL rule #12 (time-box approach switching).
# Inspired by Hermes Agent's tool_guardrails.py fingerprinting system.
#
# Tracks tool call fingerprints per session. Warns after 3 identical calls,
# strongly warns after 5. Read/Glob/Grep/WebFetch/Agent are excluded since
# repetition is normal for those tools.

set -euo pipefail

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
[[ -z "$TOOL" ]] && exit 0

# Skip tools where repetition is normal (search, read, delegation)
case "$TOOL" in
  Read|Glob|Grep|WebFetch|WebSearch|Agent|SendMessage|AskUserQuestion|Skill) exit 0 ;;
esac

# Create fingerprint from tool_name + tool_input
FINGERPRINT=$(printf '%s' "$INPUT" | jq -cS '{t: .tool_name, i: .tool_input}' 2>/dev/null | sha256sum | cut -d' ' -f1) || exit 0

# Session identity: parse session_id from the PostToolUse hook JSON on stdin
# (same pattern as lib/stop-hook-guard.sh). PPID is unreliable across subshells
# and collides when multiple sessions share a parent, so it is only a fallback.
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
[[ -z "$SESSION_ID" ]] && SESSION_ID="$PPID"
# Sanitize to a safe filename component
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9_.-')
[[ -z "$SESSION_ID" ]] && exit 0

STATE_DIR="/tmp/claude-loop-guard"
mkdir -p "$STATE_DIR" 2>/dev/null || true
STATE_FILE="$STATE_DIR/${SESSION_ID}.log"

# Cleanup: remove state files older than 4 hours (non-blocking)
find "$STATE_DIR" -name '*.log' -mmin +240 -delete 2>/dev/null &

# Append fingerprint with tool name for debugging
echo "${FINGERPRINT} ${TOOL}" >> "$STATE_FILE"

# Count occurrences of this fingerprint
COUNT=$(grep -c "^${FINGERPRINT} " "$STATE_FILE" 2>/dev/null || true)

if [[ "$COUNT" -ge 5 ]]; then
  echo "TOOL LOOP DETECTED: '$TOOL' called with identical arguments $COUNT times this session. STOP retrying the same approach. Try a fundamentally different strategy (ESSENTIAL rule #12). If stuck, spawn a debugger agent for fresh analysis."
elif [[ "$COUNT" -ge 3 ]]; then
  echo "TOOL LOOP WARNING: '$TOOL' called with identical arguments $COUNT times. You may be stuck in a retry loop. Consider changing your approach before continuing."
fi

exit 0
