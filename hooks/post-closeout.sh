#!/bin/bash
# Post closeout summaries to Discord #closeout channel
# Triggered by the Stop hook — only fires when user prompt contains "--closeout"
# Requires DISCORD_CLOSEOUT_WEBHOOK_URL set in ~/.env

set -euo pipefail

# --- Credential Resolution ---
if [ -z "${DISCORD_CLOSEOUT_WEBHOOK_URL:-}" ]; then
  [ -f "$HOME/.env" ] && source "$HOME/.env"
fi

if [ -z "${DISCORD_CLOSEOUT_WEBHOOK_URL:-}" ]; then
  exit 0
fi

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

# Truncate for Discord embed limit
MAX_LEN=3900
if [ ${#LAST_ASSISTANT_MSG} -gt $MAX_LEN ]; then
  LAST_ASSISTANT_MSG="${LAST_ASSISTANT_MSG:0:$MAX_LEN}..."
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Post as embed
PAYLOAD=$(python3 -c "
import json, sys
msg = sys.argv[1]
project = sys.argv[2]
ts = sys.argv[3]
print(json.dumps({
    'username': 'Claude Closeout',
    'embeds': [{
        'title': f'Session Closeout: {project}',
        'description': msg,
        'color': 3066993,
        'footer': {'text': ts}
    }]
}))
" "$LAST_ASSISTANT_MSG" "$PROJECT" "$TIMESTAMP")

curl -s -X POST "$DISCORD_CLOSEOUT_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  -o /dev/null --max-time 10 2>/dev/null || true

exit 0
