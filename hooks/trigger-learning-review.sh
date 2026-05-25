#!/usr/bin/env bash
# trigger-learning-review.sh — Stop hook that triggers the learning agent
# after significant sessions, complementing the 8-hour cron schedule.
# Inspired by Hermes Agent's per-turn background review fork.
#
# "Significant" = 10+ tool uses AND 3+ user messages.
# Rate-limited: won't trigger if the learning pass ran in the last 30 minutes.

source "$(dirname "$0")/lib/stop-hook-guard.sh"
stop_hook_init "trigger-learning-review"

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

# Count tool uses and user messages as significance proxies
TOOL_COUNT=$(grep -c '"type":"tool_use"\|"type": "tool_use"' "$TRANSCRIPT" 2>/dev/null || true)
USER_COUNT=$(grep -c '"role":"user"\|"role": "user"' "$TRANSCRIPT" 2>/dev/null || true)

# Skip trivial sessions
[[ "$TOOL_COUNT" -lt 10 || "$USER_COUNT" -lt 3 ]] && exit 0

# Rate limit: don't trigger if ran within last 30 minutes
RATE_FILE="/tmp/learning-review-last-trigger"
if [[ -f "$RATE_FILE" ]]; then
  LAST=$(stat -c %Y "$RATE_FILE" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  [[ $((NOW - LAST)) -lt 1800 ]] && exit 0
fi
touch "$RATE_FILE"

RUNNER="$HOME/repos/autonomousDev-private/learnings-pass/run.sh"
[[ -x "$RUNNER" ]] || exit 0

# Fire-and-forget in background
nohup "$RUNNER" >> /tmp/learning-review-triggered.log 2>&1 &

exit 0
