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

  # Next.js chunk integrity check: verify JS chunks referenced in HTML actually load.
  # Stale standalone builds serve HTML referencing chunk hashes that no longer exist,
  # causing client-side "page couldn't load" while health API returns 200.
  IS_NEXTJS=$(jq -r --arg svc "$SVC" '.services[$svc].nextjs // false' "$REGISTRY" 2>/dev/null)
  if [ "$IS_NEXTJS" = "true" ]; then
    FIRST_URL=$(jq -r --arg svc "$SVC" '.services[$svc].urls[0] // empty' "$REGISTRY" 2>/dev/null)
    if [ -n "$FIRST_URL" ]; then
      PAGE_HTML=$(curl -sL --max-time 10 "$FIRST_URL" 2>/dev/null || true)
      # Extract first /_next/static/chunks/ JS URL from the HTML
      CHUNK_PATH=$(echo "$PAGE_HTML" | grep -oP '/_next/static/chunks/[^"'"'"'\s]+\.js' | head -1 || true)
      if [ -n "$CHUNK_PATH" ]; then
        # Build absolute URL: strip path from FIRST_URL to get origin+basepath
        BASE_URL=$(echo "$FIRST_URL" | sed 's|/$||')
        CHUNK_URL="${BASE_URL}${CHUNK_PATH}"
        CHUNK_CODE=$(curl -sf --max-time 8 -o /dev/null -w "%{http_code}" "$CHUNK_URL" 2>/dev/null || echo "000")
        if [ "$CHUNK_CODE" = "200" ]; then
          PASSES="${PASSES}  [PASS] ${SVC} chunk integrity (${CHUNK_CODE})\n"
        else
          FAILURES="${FAILURES}  [FAIL] ${SVC} stale build: JS chunk returned HTTP ${CHUNK_CODE} at ${CHUNK_URL}\n"
        fi
      fi
    fi
  fi

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
