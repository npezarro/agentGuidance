#!/bin/bash
# Post each Claude Code turn to Discord #cli-interactions via webhook
# Triggered by the Stop hook event
# Requires DISCORD_WEBHOOK_URL set in .env or environment
#
# Threading model:
#   - First turn of a session: new top-level embed + thread
#   - Subsequent turns in same session: reply inside the thread
#   - State persisted in ~/.cache/discord-threads/<session_id>

set -euo pipefail

# --- Credential Resolution ---
if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  for envfile in "$HOME/.env" $HOME/.env $HOME/discord-bot/.env; do
    if [ -f "$envfile" ]; then
      source "$envfile"
      break
    fi
  done
fi

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  exit 0  # No webhook URL -- skip silently
fi

# --- Bot token (needed for thread creation) ---
BOT_TOKEN_CACHE="$HOME/.cache/discord-bot-token"
_get_bot_token() {
  if [ -f "$BOT_TOKEN_CACHE" ]; then
    cat "$BOT_TOKEN_CACHE"
    return
  fi
  local token
  token=$(ssh REDACTED_HOST 'grep -oP "DISCORD_BOT_TOKEN=\K.*" /home/REDACTED_USER/discord-bot/.env' 2>/dev/null) || true
  if [ -n "$token" ]; then
    mkdir -p "$(dirname "$BOT_TOKEN_CACHE")"
    echo "$token" > "$BOT_TOKEN_CACHE"
    chmod 600 "$BOT_TOKEN_CACHE"
    echo "$token"
  fi
}

# --- Thread state directory ---
THREAD_STATE_DIR="$HOME/.cache/discord-threads"
mkdir -p "$THREAD_STATE_DIR"

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
  USER_PROMPT=$(jq -rs '
    [.[] | select(.type == "user")] | last |
    if .message.content | type == "string" then .message.content
    elif .message.content | type == "array" then
      [.message.content[] | select(.type == "text") | .text] | join("\n")
    else empty end // empty
  ' "$TRANSCRIPT_PATH" 2>/dev/null || true)
fi

# Redact sensitive info
LAST_ASSISTANT_MSG=$(echo "$LAST_ASSISTANT_MSG" | redact_sensitive)
USER_PROMPT=$(echo "$USER_PROMPT" | redact_sensitive)

# Truncate prompt for embed field (Discord field value limit: 1024 chars)
if [ ${#USER_PROMPT} -gt 1000 ]; then
  USER_PROMPT="${USER_PROMPT:0:997}..."
fi

# --- Threading logic ---
THREAD_FILE="$THREAD_STATE_DIR/${SESSION_ID}"
EXISTING_THREAD_ID=""
if [ -n "$SESSION_ID" ] && [ -f "$THREAD_FILE" ]; then
  EXISTING_THREAD_ID=$(cat "$THREAD_FILE")
fi

MAX_EMBED_DESC=3900
RESPONSE_DISPLAY="$LAST_ASSISTANT_MSG"
OVERFLOW=""

if [ ${#LAST_ASSISTANT_MSG} -gt $MAX_EMBED_DESC ]; then
  RESPONSE_DISPLAY="${LAST_ASSISTANT_MSG:0:$MAX_EMBED_DESC}..."
  OVERFLOW="${LAST_ASSISTANT_MSG:$MAX_EMBED_DESC}"
fi

# --- Helper: post chunked text to a thread via webhook ---
post_to_thread() {
  local thread_id="$1"
  local text="$2"
  local remaining="$text"
  local chunk_num=0

  while [ -n "$remaining" ] && [ $chunk_num -lt 5 ]; do
    local chunk="${remaining:0:1990}"
    remaining="${remaining:1990}"
    chunk_num=$((chunk_num + 1))

    curl -s -X POST "${DISCORD_WEBHOOK_URL}?wait=true&thread_id=${thread_id}" \
      -H "Content-Type: application/json" \
      -d "$(python3 -c "import json,sys; print(json.dumps({'username': 'Claude Agent', 'content': sys.argv[1]}))" "$chunk")" \
      -o /dev/null --max-time 10 2>/dev/null || true

    [ -n "$remaining" ] && sleep 0.5
  done
}

if [ -n "$EXISTING_THREAD_ID" ]; then
  # --- Subsequent turn: post into existing thread ---
  THREAD_MSG="**Prompt:** ${USER_PROMPT:-(none)}

${RESPONSE_DISPLAY}"

  post_to_thread "$EXISTING_THREAD_ID" "$THREAD_MSG"

  if [ -n "$OVERFLOW" ]; then
    post_to_thread "$EXISTING_THREAD_ID" "$OVERFLOW"
  fi

else
  # --- First turn: new top-level embed + create thread ---

  TITLE=$(echo "$LAST_ASSISTANT_MSG" | grep -m1 -E '^#{1,4} ' | sed 's/^#\+ //' | head -c 256)
  if [ -z "$TITLE" ]; then
    TITLE="${PROJECT} -- ${TIMESTAMP}"
  fi

  FIELDS="[]"
  if [ -n "$USER_PROMPT" ]; then
    FIELDS=$(jq -n --arg prompt "$USER_PROMPT" '[{"name": "Prompt", "value": $prompt, "inline": false}]')
  fi
  FIELDS=$(echo "$FIELDS" | jq --arg proj "$PROJECT" --arg sid "${SESSION_ID:0:8}" '. + [{"name": "Project", "value": $proj, "inline": true}, {"name": "Session", "value": $sid, "inline": true}]')

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

  RESPONSE=$(curl -s -X POST "${DISCORD_WEBHOOK_URL}?wait=true" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    --max-time 10 2>/dev/null || echo "{}")

  MSG_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)

  # Create a thread from the top-level message
  if [ -n "$MSG_ID" ] && [ -n "$SESSION_ID" ]; then
    BOT_TOKEN=$(_get_bot_token)
    if [ -n "$BOT_TOKEN" ]; then
      CHANNEL_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('channel_id',''))" 2>/dev/null || true)

      if [ -n "$CHANNEL_ID" ]; then
        THREAD_NAME="${PROJECT}: ${TITLE:0:80}"
        THREAD_RESPONSE=$(curl -s -X POST "https://discord.com/api/v10/channels/${CHANNEL_ID}/messages/${MSG_ID}/threads" \
          -H "Authorization: Bot ${BOT_TOKEN}" \
          -H "Content-Type: application/json" \
          -d "$(python3 -c "import json,sys; print(json.dumps({'name': sys.argv[1][:100], 'auto_archive_duration': 1440}))" "$THREAD_NAME")" \
          --max-time 10 2>/dev/null || echo "{}")

        NEW_THREAD_ID=$(echo "$THREAD_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)

        if [ -n "$NEW_THREAD_ID" ]; then
          echo "$NEW_THREAD_ID" > "$THREAD_FILE"
        fi
      fi
    fi
  fi

  # Post overflow into the thread (or channel if no thread was created)
  if [ -n "$OVERFLOW" ]; then
    OVERFLOW_THREAD_ID=""
    [ -n "$SESSION_ID" ] && [ -f "$THREAD_FILE" ] && OVERFLOW_THREAD_ID=$(cat "$THREAD_FILE")

    if [ -n "$OVERFLOW_THREAD_ID" ]; then
      post_to_thread "$OVERFLOW_THREAD_ID" "$OVERFLOW"
    else
      # Fallback: post to channel if thread creation failed
      CHUNK_SIZE=1990
      REMAINING="$OVERFLOW"
      CHUNK_NUM=0
      while [ -n "$REMAINING" ] && [ $CHUNK_NUM -lt 3 ]; do
        CHUNK="${REMAINING:0:$CHUNK_SIZE}"
        REMAINING="${REMAINING:$CHUNK_SIZE}"
        CHUNK_NUM=$((CHUNK_NUM + 1))

        sleep 0.5
        curl -s -X POST "$DISCORD_WEBHOOK_URL" \
          -H "Content-Type: application/json" \
          -d "$(python3 -c "import json,sys; print(json.dumps({'username': 'Claude Agent', 'content': sys.argv[1]}))" "$CHUNK")" \
          -o /dev/null \
          --max-time 10 2>/dev/null || true
      done
    fi
  fi
fi

# Clean up stale thread files (older than 7 days)
find "$THREAD_STATE_DIR" -type f -mtime +7 -delete 2>/dev/null || true

exit 0
