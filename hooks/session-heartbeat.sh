#!/usr/bin/env bash
# session-heartbeat.sh — PostToolUse hook.
# Refreshes an "interactive session active" heartbeat so the autonomousDev crons can
# DEFER while a human-driven session is live, avoiding the concurrent-agent shared-tree
# collisions (two writers in one ~/repos/<repo> checkout). Headless `claude -p` runs (the
# crons themselves, VM #requests workers, pipelines) are EXCLUDED so they don't self-block.
# Always exits 0; pure side effect, no output.
#
# ALSO refreshes a PER-SESSION liveness marker, /tmp/claude-session-alive-{session_id}.
# The global heartbeat above answers "is a human live" (cron-vs-human). It cannot answer
# "is session X still running", which is what claim-guard.sh needs to tell a live
# concurrent writer from a stale /tmp ledger left by a session that exited weeks ago.
# Unlike the global heartbeat, the per-session marker is written for headless runs too:
# a `claude -p` worker writing ~/repos/<app> can clobber an interactive session just as
# easily, so collision detection must see it.
set -uo pipefail

# --- per-session liveness marker (all sessions, interactive and headless) ---
SID="${CLAUDE_SESSION_ID:-}"
if [ -z "$SID" ] && [ ! -t 0 ]; then
  HB_INPUT=$(timeout 2 cat 2>/dev/null || true)
  SID=$(printf '%s' "$HB_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
fi
[ -n "$SID" ] && touch "/tmp/claude-session-alive-${SID}" 2>/dev/null

# --- identify the claude invocation by walking up the process tree (/proc on Linux/WSL) ---
CMDLINE="${SESSION_HB_CMDLINE_OVERRIDE:-}"
if [ -z "$CMDLINE" ]; then
  pid="$PPID"
  for _ in 1 2 3 4 5 6; do
    if [ -r "/proc/$pid/cmdline" ]; then
      c="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
      next="$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null || echo "")"
    else
      break
    fi
    if printf '%s' "$c" | grep -qE '(^|/| )claude(\.exe)?( |$)'; then CMDLINE="$c"; break; fi
    pid="$next"
    { [ -z "$pid" ] || [ "$pid" = "0" ] || [ "$pid" = "1" ]; } && break
  done
fi

# Can't identify the invocation, or it's headless (-p / --print) -> do NOT heartbeat.
[ -n "$CMDLINE" ] || exit 0
printf '%s' " $CMDLINE " | grep -qE ' (-p|--print)([ =]|$)' && exit 0

mkdir -p "$HOME/.claude" 2>/dev/null || true
touch "$HOME/.claude/interactive-session.heartbeat" 2>/dev/null || true
exit 0
