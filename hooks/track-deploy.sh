#!/usr/bin/env bash
# PostToolUse hook for Bash: detects deployment commands and tracks deployed services.
# Writes service names to /tmp/claude-deploys-{session_id} for the Stop hook to verify.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

[ -z "$CMD" ] || [ -z "$SID" ] && exit 0

TRACKER="/tmp/claude-deploys-${SID}"
REGISTRY="$HOME/repos/privateContext/deploy-registry.json"

[ -f "$REGISTRY" ] || exit 0

# Detect pm2 restart commands
if echo "$CMD" | grep -qE 'pm2 (restart|start|reload)'; then
  # Extract the PM2 process name
  PM2_NAME=$(echo "$CMD" | grep -oE 'pm2 (restart|start|reload) [^ ]+' | awk '{print $3}' || true)
  if [ -n "$PM2_NAME" ]; then
    # Look up service by pm2 name in registry
    SVC=$(jq -r --arg pm2 "$PM2_NAME" '.services | to_entries[] | select(.value.pm2 == $pm2) | .key' "$REGISTRY" 2>/dev/null || true)
    if [ -n "$SVC" ]; then
      echo "$SVC" >> "$TRACKER"
      sort -u -o "$TRACKER" "$TRACKER"
    fi
  fi
fi

# Detect SSH deploy patterns (git pull + pm2 on VM)
if echo "$CMD" | grep -qE 'ssh.*pezant.*pm2 restart'; then
  PM2_NAME=$(echo "$CMD" | grep -oE 'pm2 restart [^ "]+' | awk '{print $3}' | tr -d "'" | tr -d '"' || true)
  if [ -n "$PM2_NAME" ]; then
    SVC=$(jq -r --arg pm2 "$PM2_NAME" '.services | to_entries[] | select(.value.pm2 == $pm2) | .key' "$REGISTRY" 2>/dev/null || true)
    if [ -n "$SVC" ]; then
      echo "$SVC" >> "$TRACKER"
      sort -u -o "$TRACKER" "$TRACKER"
    fi
  fi
fi

exit 0
