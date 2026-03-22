#!/usr/bin/env bash
# refetch-instructions.sh — Re-fetch the latest global agent rules mid-session.
#
# Outputs the latest agent.md (and optionally guidance files) so that a running
# Claude Code instance can incorporate updated instructions without restarting.
#
# Usage:
#   bash ~/repos/agentGuidance/scripts/refetch-instructions.sh
#   bash ~/repos/agentGuidance/scripts/refetch-instructions.sh --with-guidance

set -euo pipefail

AGENT_MD_URL="https://raw.githubusercontent.com/npezarro/agentGuidance/main/agent.md"
GUIDANCE_BASE_URL="https://raw.githubusercontent.com/npezarro/agentGuidance/main/guidance"
LOCAL_FALLBACK="$HOME/repos/agentGuidance/agent.md"
LOCAL_GUIDANCE="$HOME/repos/agentGuidance/guidance"

WITH_GUIDANCE=false
if [[ "${1:-}" == "--with-guidance" ]]; then
  WITH_GUIDANCE=true
fi

echo "=== REFETCHED INSTRUCTIONS ($(date -Iseconds)) ==="
echo ""

# Try remote first, fall back to local
AGENT_MD=$(curl -sf --max-time 10 "$AGENT_MD_URL" 2>/dev/null) || {
  if [ -f "$LOCAL_FALLBACK" ]; then
    echo "[refetch] Remote fetch failed, using local copy"
    AGENT_MD=$(cat "$LOCAL_FALLBACK")
  else
    echo "[refetch] ERROR: Could not fetch agent.md from remote or local" >&2
    exit 1
  fi
}

echo "$AGENT_MD"

if $WITH_GUIDANCE; then
  echo ""
  echo "=== GUIDANCE FILES ==="

  GUIDANCE_FILES=(
    "ab-testing.md"
    "session-lifecycle.md"
    "operational-safety.md"
    "resource-awareness.md"
    "process-hygiene.md"
  )

  for gf in "${GUIDANCE_FILES[@]}"; do
    echo ""
    echo "--- guidance/$gf ---"
    CONTENT=$(curl -sf --max-time 5 "${GUIDANCE_BASE_URL}/${gf}" 2>/dev/null) || {
      if [ -f "$LOCAL_GUIDANCE/$gf" ]; then
        CONTENT=$(cat "$LOCAL_GUIDANCE/$gf")
      else
        CONTENT="[not available]"
      fi
    }
    echo "$CONTENT"
  done
fi

echo ""
echo "=== END REFETCHED INSTRUCTIONS ==="
