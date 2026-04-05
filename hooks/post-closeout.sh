#!/bin/bash
# Post closeout summaries to Discord #closeout channel with threading and chunking.
# Triggered by the Stop hook — only fires when user prompt contains "--closeout"
# Requires DISCORD_CLOSEOUT_WEBHOOK_URL set in ~/.env
#
# Posts a top-level embed with project name + summary, then creates a thread
# with the full closeout content chunked into 1990-char messages (no truncation).

set -euo pipefail

# --- Credential Resolution ---
if [ -z "${DISCORD_CLOSEOUT_WEBHOOK_URL:-}" ]; then
  [ -f "$HOME/.env" ] && source "$HOME/.env"
fi

if [ -z "${DISCORD_CLOSEOUT_WEBHOOK_URL:-}" ]; then
  exit 0
fi

CLOSEOUT_CHANNEL_ID="REDACTED_CHANNEL_ID"

# Bot token — fetched from VM on first use, cached locally
BOT_TOKEN_CACHE="$HOME/.cache/discord-bot-token"
_get_bot_token() {
  if [ -f "$BOT_TOKEN_CACHE" ]; then
    cat "$BOT_TOKEN_CACHE"
    return
  fi
  local token
  token=$(ssh pezant-vm 'grep -oP "DISCORD_BOT_TOKEN=\K.*" /home/REDACTED_VM_USER/centralDiscord/.env' 2>/dev/null)
  if [ -n "$token" ]; then
    mkdir -p "$(dirname "$BOT_TOKEN_CACHE")"
    echo "$token" > "$BOT_TOKEN_CACHE"
    chmod 600 "$BOT_TOKEN_CACHE"
    echo "$token"
  fi
}

# Read hook input from stdin
INPUT=$(cat)

LAST_ASSISTANT_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
PROJECT=$(basename "$CWD")

# Only fire if the user's last prompt was a closeout request
USER_PROMPT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  USER_PROMPT=$(jq -rs '[.[] | select(.type == "user" and (.message.content | type == "string"))] | last | .message.content // empty' "$TRANSCRIPT_PATH" 2>/dev/null || true)
fi

if ! echo "$USER_PROMPT" | grep -qi '\-\-closeout\|closeout'; then
  exit 0
fi

if [ -z "$LAST_ASSISTANT_MSG" ]; then
  exit 0
fi

# Redact sensitive info
redact_sensitive() {
  sed -E \
    -e 's/ghp_[A-Za-z0-9]{36,}/[REDACTED]/g' \
    -e 's/github_pat_[A-Za-z0-9_]{40,}/[REDACTED]/g' \
    -e 's/sk-[A-Za-z0-9]{20,}/[REDACTED]/g' \
    -e 's/(SECRET|TOKEN|API_KEY|PASSWORD|CREDENTIAL)=[^ "'\'']+/\1=[REDACTED]/g' \
    -e 's|https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+|[REDACTED_WEBHOOK]|g' \
    -e 's/[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}/[REDACTED]/g'
}

LAST_ASSISTANT_MSG=$(echo "$LAST_ASSISTANT_MSG" | redact_sensitive)

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# --- Helper: post via bot API ---
bot_post() {
  local msg="$1"
  local channel="$2"
  local token
  token=$(_get_bot_token)
  if [ -z "$token" ]; then
    echo "Warning: Could not fetch bot token. Thread posting will fail." >&2
    return 1
  fi

  msg="${msg:0:1990}"

  curl -s -X POST "https://discord.com/api/v10/channels/${channel}/messages" \
    -H "Authorization: Bot ${token}" \
    -H "Content-Type: application/json" \
    --max-time 10 \
    -d "$(python3 -c "import json,sys; print(json.dumps({'content': sys.argv[1]}))" "$msg")"
}

# --- Helper: create thread from a message ---
create_thread() {
  local message_id="$1"
  local name="$2"
  local token
  token=$(_get_bot_token)
  [ -z "$token" ] && return 1

  name="${name:0:100}"

  curl -s -X POST "https://discord.com/api/v10/channels/${CLOSEOUT_CHANNEL_ID}/messages/${message_id}/threads" \
    -H "Authorization: Bot ${token}" \
    -H "Content-Type: application/json" \
    --max-time 10 \
    -d "$(python3 -c "import json,sys; print(json.dumps({'name': sys.argv[1], 'auto_archive_duration': 1440}))" "$name")"
}

# --- Extract summary for the top-level embed ---
# Take the first ~300 chars or first paragraph as the embed summary
SUMMARY=$(echo "$LAST_ASSISTANT_MSG" | head -c 300)
if [ ${#LAST_ASSISTANT_MSG} -gt 300 ]; then
  SUMMARY="${SUMMARY}..."
fi

# --- Post top-level embed ---
PAYLOAD=$(python3 -c "
import json, sys
summary = sys.argv[1]
project = sys.argv[2]
ts = sys.argv[3]
total_len = int(sys.argv[4])
print(json.dumps({
    'username': 'Claude Closeout',
    'embeds': [{
        'title': f'Session Closeout: {project}',
        'description': summary,
        'color': 3066993,
        'footer': {'text': f'{ts} | Full report in thread ({total_len:,} chars)'}
    }]
}))
" "$SUMMARY" "$PROJECT" "$TIMESTAMP" "${#LAST_ASSISTANT_MSG}")

RESPONSE=$(curl -s -X POST "${DISCORD_CLOSEOUT_WEBHOOK_URL}?wait=true" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  --max-time 10 2>/dev/null || echo '{}')

MSG_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

if [ -z "$MSG_ID" ]; then
  # Embed post failed — fall back to plain chunked messages (no thread)
  REMAINING="$LAST_ASSISTANT_MSG"
  while [ -n "$REMAINING" ]; do
    CHUNK="${REMAINING:0:1990}"
    REMAINING="${REMAINING:1990}"
    curl -s -X POST "${DISCORD_CLOSEOUT_WEBHOOK_URL}" \
      -H "Content-Type: application/json" \
      --max-time 10 \
      -d "$(python3 -c "import json,sys; print(json.dumps({'username': 'Claude Closeout', 'content': sys.argv[1]}))" "$CHUNK")" \
      -o /dev/null 2>/dev/null || true
    [ -n "$REMAINING" ] && sleep 1
  done
  exit 0
fi

# --- Create thread and post full content in chunks ---
THREAD_NAME="Session Closeout: ${PROJECT}"
THREAD_RESPONSE=$(create_thread "$MSG_ID" "$THREAD_NAME" 2>/dev/null || echo '{}')
THREAD_ID=$(echo "$THREAD_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

if [ -n "$THREAD_ID" ]; then
  # Post full closeout in 1990-char chunks inside the thread
  REMAINING="$LAST_ASSISTANT_MSG"
  while [ -n "$REMAINING" ]; do
    CHUNK="${REMAINING:0:1990}"
    REMAINING="${REMAINING:1990}"
    bot_post "$CHUNK" "$THREAD_ID" > /dev/null 2>&1
    [ -n "$REMAINING" ] && sleep 1
  done
else
  # Thread creation failed — post full content as follow-up webhook messages
  echo "Warning: Thread creation failed. Posting as follow-up messages." >&2
  REMAINING="$LAST_ASSISTANT_MSG"
  while [ -n "$REMAINING" ]; do
    CHUNK="${REMAINING:0:1990}"
    REMAINING="${REMAINING:1990}"
    curl -s -X POST "${DISCORD_CLOSEOUT_WEBHOOK_URL}" \
      -H "Content-Type: application/json" \
      --max-time 10 \
      -d "$(python3 -c "import json,sys; print(json.dumps({'username': 'Claude Closeout', 'content': sys.argv[1]}))" "$CHUNK")" \
      -o /dev/null 2>/dev/null || true
    [ -n "$REMAINING" ] && sleep 1
  done
fi

exit 0
