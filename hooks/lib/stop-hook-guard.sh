#!/usr/bin/env bash
# stop-hook-guard.sh — Shared guard library for Stop hooks.
# Source this at the top of any Stop hook to get standardized safety checks.
#
# Usage:
#   source "$(dirname "$0")/lib/stop-hook-guard.sh"
#   stop_hook_init "my-hook-name"
#
# For hooks that invoke Claude:
#   stop_hook_init "my-hook-name" --invokes-claude
#
# Available after init:
#   HOOK_INPUT     — raw stdin content (JSON from hook framework)
#   SESSION_ID     — session ID
#   TRANSCRIPT     — path to transcript file
#   HOOK_LOCKDIR   — /tmp/claude-hook-locks
#
# Functions:
#   stop_hook_init        — run all guards, exit early if unsafe
#   stop_hook_cleanup     — release lock (called automatically via trap)
#   stop_hook_rate_ok     — check per-hour invocation rate (returns 0/1)

set -uo pipefail

HOOK_LOCKDIR="/tmp/claude-hook-locks"
HOOK_RATEDIR="/tmp/claude-hook-rates"
HOOK_INPUT=""
SESSION_ID=""
TRANSCRIPT=""

_hook_name=""
_hook_invokes_claude=false
_hook_lockfile=""

stop_hook_init() {
  _hook_name="${1:?Usage: stop_hook_init <hook-name> [--invokes-claude]}"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --invokes-claude) _hook_invokes_claude=true ;;
    esac
    shift
  done

  # --- Read stdin (hook framework pipes JSON) ---
  HOOK_INPUT=$(cat)
  SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
  TRANSCRIPT=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

  # --- Guard 1: Env var circuit breaker (Claude-invoking hooks) ---
  if [ "$_hook_invokes_claude" = true ]; then
    local guard_var="CLAUDE_HOOK_${_hook_name^^}"
    guard_var="${guard_var//-/_}"  # normalize dashes to underscores
    if [ "${!guard_var:-}" = "1" ]; then
      exit 0
    fi
    # Export the guard so any Claude subprocess inherits it
    export "${guard_var}=1"
  fi

  # --- Guard 2: Lockfile (prevent concurrent execution of same hook) ---
  mkdir -p "$HOOK_LOCKDIR" 2>/dev/null || true
  _hook_lockfile="${HOOK_LOCKDIR}/${_hook_name}.lock"
  if [ -f "$_hook_lockfile" ]; then
    local old_pid
    old_pid=$(cat "$_hook_lockfile" 2>/dev/null || echo "")
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      # Another instance is running, bail
      exit 0
    fi
    # Stale lock, remove it
    rm -f "$_hook_lockfile"
  fi
  echo $$ > "$_hook_lockfile"
  trap 'stop_hook_cleanup' EXIT

  # --- Guard 3: Rate limit (Claude-invoking hooks: max 5/hour) ---
  if [ "$_hook_invokes_claude" = true ]; then
    if ! stop_hook_rate_ok 5; then
      exit 0
    fi
    _record_invocation
  fi
}

stop_hook_cleanup() {
  rm -f "$_hook_lockfile" 2>/dev/null || true
}

# Check if this hook has been invoked fewer than $1 times in the last hour.
stop_hook_rate_ok() {
  local max_per_hour="${1:-5}"
  mkdir -p "$HOOK_RATEDIR" 2>/dev/null || true
  local rate_file="${HOOK_RATEDIR}/${_hook_name}.log"
  [ -f "$rate_file" ] || return 0

  local cutoff
  cutoff=$(date -d '1 hour ago' +%s 2>/dev/null || date -v-1H +%s 2>/dev/null || echo "0")
  local count=0
  while IFS= read -r ts; do
    [ "$ts" -ge "$cutoff" ] 2>/dev/null && count=$((count + 1))
  done < "$rate_file"

  [ "$count" -lt "$max_per_hour" ]
}

_record_invocation() {
  mkdir -p "$HOOK_RATEDIR" 2>/dev/null || true
  local rate_file="${HOOK_RATEDIR}/${_hook_name}.log"
  date +%s >> "$rate_file"
  # Prune entries older than 1 hour
  local cutoff
  cutoff=$(date -d '1 hour ago' +%s 2>/dev/null || date -v-1H +%s 2>/dev/null || echo "0")
  if [ -f "$rate_file" ]; then
    local tmp
    tmp=$(mktemp)
    while IFS= read -r ts; do
      [ "$ts" -ge "$cutoff" ] 2>/dev/null && echo "$ts"
    done < "$rate_file" > "$tmp"
    mv "$tmp" "$rate_file"
  fi
}
