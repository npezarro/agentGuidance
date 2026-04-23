#!/usr/bin/env bash
# Stop hook: verifies health of services deployed during this session.
# Reads /tmp/claude-deploys-{session_id} for the list of deployed services,
# then checks health endpoints and user-facing URLs from deploy-registry.json.
# Outputs JSON with systemMessage if any checks fail.

set -euo pipefail

INPUT=$(cat)
SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

[ -z "$SID" ] && exit 0

TRACKER="/tmp/claude-deploys-${SID}"

# No deploys tracked this session, skip
[ -f "$TRACKER" ] || exit 0

REGISTRY="$HOME/repos/privateContext/deploy-registry.json"
[ -f "$REGISTRY" ] || exit 0

SERVICES=$(cat "$TRACKER")
[ -z "$SERVICES" ] && exit 0

FAILURES=""
PASSES=""

while IFS= read -r SVC; do
  [ -z "$SVC" ] && continue

  # Get health URL
  HEALTH=$(jq -r --arg svc "$SVC" '.services[$svc].health // empty' "$REGISTRY" 2>/dev/null)
  if [ -n "$HEALTH" ]; then
    HTTP_CODE=$(curl -sf --max-time 8 -o /dev/null -w "%{http_code}" "$HEALTH" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
      PASSES="${PASSES}  [PASS] ${SVC} health (${HTTP_CODE})\n"
    else
      FAILURES="${FAILURES}  [FAIL] ${SVC} health: HTTP ${HTTP_CODE} at ${HEALTH}\n"
    fi
  fi

  # Get user-facing URLs
  URLS=$(jq -r --arg svc "$SVC" '.services[$svc].urls[]? // empty' "$REGISTRY" 2>/dev/null)
  while IFS= read -r URL; do
    [ -z "$URL" ] && continue
    HTTP_CODE=$(curl -sf --max-time 8 -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
      PASSES="${PASSES}  [PASS] ${SVC} page (${HTTP_CODE})\n"
    else
      FAILURES="${FAILURES}  [FAIL] ${SVC} page: HTTP ${HTTP_CODE} at ${URL}\n"
    fi
  done <<< "$URLS"

done <<< "$SERVICES"

# Clean up tracker
rm -f "$TRACKER"

# Build output
if [ -n "$FAILURES" ]; then
  MSG="DEPLOY VERIFICATION FAILED:\n${FAILURES}"
  if [ -n "$PASSES" ]; then
    MSG="${MSG}\nPassed:\n${PASSES}"
  fi
  printf '{"decision":"block","reason":"%s"}' "$(printf "$MSG" | tr '\n' ' ')"
else
  if [ -n "$PASSES" ]; then
    printf '{"systemMessage":"Deploy verification passed:\\n%s"}' "$(printf "$PASSES" | sed 's/"/\\"/g' | tr '\n' ' ')"
  fi
fi

exit 0
