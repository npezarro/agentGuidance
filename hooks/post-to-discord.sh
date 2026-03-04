#!/bin/bash
# Post each Claude Code turn to Discord via webhook
# Triggered by the Stop hook event
# Requires DISCORD_WEBHOOK_URL set in .env or environment

set -euo pipefail

# --- Credential Resolution ---
if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  for envfile in "$HOME/.env" /home/generatedByTermius/.env /home/generatedByTermius/centralDiscord/.env; do
    if [ -f "$envfile" ]; then
      source "$envfile"
      break
    fi
  done
fi

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  exit 0  # No webhook URL — skip silently
fi

# --- Redaction ---
redact_sensitive() {
  sed -E \
    -e 's/[A-Za-z0-9]{4} [A-Za-z0-9]{4} [A-Za-z0-9]{4} [A-Za-z0-9]{4} [A-Za-z0-9]{4} [A-Za-z0-9]{4}/[REDACTED_APP_PASSWORD]/g' \
    -e 's/ghp_[A-Za-z0-9]{36,}/[REDACTED_GITHUB_TOKEN]/g' \
    -e 's/github_pat_[A-Za-z0-9_]{40,}/[REDACTED_GITHUB_PAT]/g' \
    -e 's/sk-proj-[A-Za-z0-9_-]{40,}/[REDACTED_API_KEY]/g' \
    -e 's/sk-[A-Za-z0-9]{20,}/[REDACTED_API_KEY]/g' \
    -e 's/key-[A-Za-z0-9]{20,}/[REDACTED_API_KEY]/g' \
    -e 's/Bearer [A-Za-z0-9._-]{20,}/Bearer [REDACTED_BEARER]/g' \
    -e 's/(SECRET|_SECRET|CLIENT_SECRET|TOKEN|API_KEY|OPENAI_API_KEY|SMTP_PASS|APP_PASSWORD|WP_APP_PASSWORD|DISCORD_BOT_TOKEN|DISCORD_WEBHOOK_URL)=[^ "'\'']+/\1=[REDACTED]/g' \
    -e 's/(PASSWORD|_PASS|_PASSWORD|CREDENTIAL|_CREDENTIAL)=[^ "'\'']+/\1=[REDACTED]/g' \
    -e 's|https?://[^:@ ]+:[^@ ]+@|https://[REDACTED_CREDS]@|g' \
    -e 's|https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+|[REDACTED_WEBHOOK_URL]|g' \
    -e 's/[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}/[REDACTED_DISCORD_TOKEN]/g'
}

# Read hook input from stdin
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
LAST_ASSISTANT_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')

# Skip if no assistant message
if [ -z "$LAST_ASSISTANT_MSG" ]; then
  exit 0
fi

# Get working directory and project name
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
PROJECT=$(basename "$CWD")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Extract the last user prompt from transcript
USER_PROMPT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  USER_PROMPT=$(jq -rs '[.[] | select(.type == "user" and (.message.content | type == "string"))] | last | .message.content // empty' "$TRANSCRIPT_PATH" 2>/dev/null || true)
fi

# Redact sensitive info
LAST_ASSISTANT_MSG=$(echo "$LAST_ASSISTANT_MSG" | redact_sensitive)
USER_PROMPT=$(echo "$USER_PROMPT" | redact_sensitive)

# Truncate prompt for embed field (Discord field value limit: 1024 chars)
if [ ${#USER_PROMPT} -gt 200 ]; then
  USER_PROMPT="${USER_PROMPT:0:197}..."
fi

# Discord has a 2000-char message limit, 4096-char embed description limit
# Use embed for the first chunk, follow-up messages for overflow
MAX_EMBED_DESC=3900
RESPONSE_DISPLAY="$LAST_ASSISTANT_MSG"
OVERFLOW=""

if [ ${#LAST_ASSISTANT_MSG} -gt $MAX_EMBED_DESC ]; then
  RESPONSE_DISPLAY="${LAST_ASSISTANT_MSG:0:$MAX_EMBED_DESC}..."
  # Capture overflow for follow-up messages (up to 6000 more chars, 3 messages)
  OVERFLOW="${LAST_ASSISTANT_MSG:$MAX_EMBED_DESC}"
fi

# --- Build embed payload ---
# Title: extract first markdown heading or use project + timestamp
TITLE=$(echo "$LAST_ASSISTANT_MSG" | grep -m1 -E '^#{1,4} ' | sed 's/^#\+ //' | head -c 256)
if [ -z "$TITLE" ]; then
  TITLE="${PROJECT} — ${TIMESTAMP}"
fi

# Build fields array
FIELDS="[]"
if [ -n "$USER_PROMPT" ]; then
  FIELDS=$(jq -n --arg prompt "$USER_PROMPT" '[{"name": "Prompt", "value": $prompt, "inline": false}]')
fi
FIELDS=$(echo "$FIELDS" | jq --arg proj "$PROJECT" --arg sid "${SESSION_ID:0:8}" '. + [{"name": "Project", "value": $proj, "inline": true}, {"name": "Session", "value": $sid, "inline": true}]')

# Post the embed
PAYLOAD=$(jq -n \
  --arg username "Claude Agent" \
  --arg title "$TITLE" \
  --arg desc "$RESPONSE_DISPLAY" \
  --argjson fields "$FIELDS" \
  --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  '{
    username: $username,
    embeds: [{
      title: $title,
      description: $desc,
      color: 7879533,
      fields: $fields,
      timestamp: $ts,
      footer: {"text": "Claude Code Agent"}
    }]
  }')

curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  -o /dev/null \
  --max-time 10 2>/dev/null || true

# Post overflow chunks as follow-up messages (plain text, 2000 char limit each)
if [ -n "$OVERFLOW" ]; then
  CHUNK_SIZE=1990
  REMAINING="$OVERFLOW"
  CHUNK_NUM=0
  while [ -n "$REMAINING" ] && [ $CHUNK_NUM -lt 3 ]; do
    CHUNK="${REMAINING:0:$CHUNK_SIZE}"
    REMAINING="${REMAINING:$CHUNK_SIZE}"
    CHUNK_NUM=$((CHUNK_NUM + 1))

    CHUNK_PAYLOAD=$(jq -n \
      --arg username "Claude Agent" \
      --arg content "\`\`\`\n${CHUNK}\n\`\`\`" \
      '{username: $username, content: $content}')

    # Small delay to maintain message order
    sleep 0.5
    curl -s -X POST "$DISCORD_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "$CHUNK_PAYLOAD" \
      -o /dev/null \
      --max-time 10 2>/dev/null || true
  done
fi

exit 0
