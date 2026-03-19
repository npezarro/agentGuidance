#!/usr/bin/env bash
# generate-crontab.sh — Reads all task configs and generates crontab entries.
# Stagger schedules to avoid concurrent Claude CLI invocations.
#
# Usage: ./generate-crontab.sh [--install]
#   Without --install: prints crontab entries to stdout
#   With --install: appends to current user's crontab (idempotent)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_DIR="$SCRIPT_DIR/tasks"
RUNNER="$SCRIPT_DIR/runner.sh"

MARKER_START="# --- recurring-tasks START ---"
MARKER_END="# --- recurring-tasks END ---"

ENTRIES=""

for conf in "$TASKS_DIR"/*.conf; do
  [ -f "$conf" ] || continue

  TASK_NAME=$(basename "$conf" .conf)
  SCHEDULE=""
  DESCRIPTION=""
  ENABLED="true"

  # Source config to get SCHEDULE, DESCRIPTION, ENABLED
  while IFS='=' read -r key value; do
    value="${value%\"}"
    value="${value#\"}"
    case "$key" in
      SCHEDULE) SCHEDULE="$value" ;;
      DESCRIPTION) DESCRIPTION="$value" ;;
      ENABLED) ENABLED="$value" ;;
    esac
  done < "$conf"

  if [ -z "$SCHEDULE" ]; then
    echo "Warning: $TASK_NAME has no SCHEDULE, skipping." >&2
    continue
  fi

  if [ "$ENABLED" = "false" ]; then
    ENTRIES="$ENTRIES# DISABLED: $TASK_NAME -- $DESCRIPTION
# $SCHEDULE $RUNNER $TASK_NAME >> $SCRIPT_DIR/logs/${TASK_NAME}-cron.log 2>&1
"
  else
    ENTRIES="$ENTRIES# $TASK_NAME -- $DESCRIPTION
$SCHEDULE $RUNNER $TASK_NAME >> $SCRIPT_DIR/logs/${TASK_NAME}-cron.log 2>&1
"
  fi
done

BLOCK="$MARKER_START
$ENTRIES$MARKER_END"

if [[ "${1:-}" == "--install" ]]; then
  EXISTING=$(crontab -l 2>/dev/null || echo "")

  # Remove old block if present
  CLEANED=$(echo "$EXISTING" | sed "/$MARKER_START/,/$MARKER_END/d")

  # Append new block
  echo "$CLEANED
$BLOCK" | crontab -

  echo "Crontab updated. Current entries:"
  crontab -l | grep -A1 "recurring-tasks"
else
  echo "$BLOCK"
fi
