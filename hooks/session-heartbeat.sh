#!/usr/bin/env bash
# session-heartbeat.sh — PostToolUse hook.
# Refreshes an "interactive session active" heartbeat so the autonomousDev crons can
# DEFER while a human-driven session is live, avoiding the concurrent-agent shared-tree
# collisions (two writers in one ~/repos/<repo> checkout). Headless `claude -p` runs (the
# crons themselves, VM #requests workers, pipelines) are EXCLUDED so they don't self-block.
# Always exits 0; pure side effect, no output.
set -uo pipefail

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
