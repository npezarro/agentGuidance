#!/usr/bin/env bash
# interactive-session-active.sh — exit 0 if an interactive Claude session is active
# (heartbeat refreshed within the staleness window), else exit 1.
#
# Used by the autonomousDev crons to DEFER while a human session is live, so a cron's
# claude -p never mutates a ~/repos/<repo> checkout that an interactive session is using.
# Heartbeat is written by hooks/session-heartbeat.sh (PostToolUse, interactive-only).
#
# Override the window with SESSION_HEARTBEAT_STALE_SECS (default 1200 = 20 min).
HB="$HOME/.claude/interactive-session.heartbeat"
STALE="${SESSION_HEARTBEAT_STALE_SECS:-1200}"

[ -f "$HB" ] || exit 1
NOW="$(date +%s)"
MT="$(stat -c %Y "$HB" 2>/dev/null || stat -f %m "$HB" 2>/dev/null || echo 0)"
[ $((NOW - MT)) -lt "$STALE" ] && exit 0 || exit 1
