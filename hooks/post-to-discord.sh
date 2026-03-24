#!/bin/bash
# Post each Claude Code turn to Discord #cli-interactions via webhook
# Triggered by the Stop hook event
# Requires DISCORD_WEBHOOK_URL set in .env or environment
#
# Threading model:
#   - First turn of a session: new top-level embed + thread
#   - Subsequent turns in same session: reply inside the thread
#   - State persisted in ~/.cache/discord-threads/<session_id>
#
# Rich logging:
#   - Extracts tool calls (Read, Edit, Bash, Grep, Glob, Write, Agent, etc.)
#     from the transcript and formats them as an activity log between
#     the user prompt and the assistant response.

set -uo pipefail

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
  if [ -n "${DISCORD_BOT_TOKEN:-}" ]; then
    echo "$DISCORD_BOT_TOKEN"
    return
  fi
  if [ -f "$BOT_TOKEN_CACHE" ]; then
    cat "$BOT_TOKEN_CACHE"
    return
  fi
  return 1
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

# --- Extract rich turn data from transcript using Python ---
# Write the extraction script to a temp file to avoid heredoc-in-subshell issues
TURN_DATA=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  PY_SCRIPT=$(mktemp /tmp/turn-extract-XXXXXX.py)
  cat > "$PY_SCRIPT" << 'PYEOF'
import json, sys, os

transcript_path = os.environ.get('TRANSCRIPT', '')
if not transcript_path:
    sys.exit(0)

entries = []
with open(transcript_path, 'r') as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue

messages = [e for e in entries if e.get('type') in ('user', 'assistant')]

last_prompt_idx = -1
for i in range(len(messages) - 1, -1, -1):
    msg = messages[i]
    if msg.get('type') != 'user':
        continue
    content = msg.get('message', {}).get('content')
    if isinstance(content, str):
        last_prompt_idx = i
        break
    if isinstance(content, list):
        has_text = any(c.get('type') == 'text' for c in content if isinstance(c, dict))
        if has_text:
            last_prompt_idx = i
            break

user_prompt = ""
if last_prompt_idx >= 0:
    content = messages[last_prompt_idx].get('message', {}).get('content')
    if isinstance(content, str):
        user_prompt = content
    elif isinstance(content, list):
        user_prompt = "\n".join(
            c.get('text', '') for c in content
            if isinstance(c, dict) and c.get('type') == 'text'
        )

tool_calls = []
if last_prompt_idx >= 0:
    for msg in messages[last_prompt_idx + 1:]:
        if msg.get('type') != 'assistant':
            continue
        content = msg.get('message', {}).get('content')
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get('type') == 'tool_use':
                tool_calls.append(block)

tool_results = {}
if last_prompt_idx >= 0:
    for msg in messages[last_prompt_idx + 1:]:
        content = msg.get('message', {}).get('content')
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'tool_result':
                tid = block.get('tool_use_id', '')
                is_error = block.get('is_error', False)
                result_content = block.get('content', '')
                if isinstance(result_content, list):
                    result_content = ' '.join(
                        c.get('text', '')[:200] for c in result_content
                        if isinstance(c, dict) and c.get('type') == 'text'
                    )
                elif isinstance(result_content, str):
                    result_content = result_content[:200]
                tool_results[tid] = {'is_error': is_error, 'preview': str(result_content)[:200]}

def shorten_path(p, max_len=60):
    if not p or len(p) <= max_len:
        return p
    home = os.path.expanduser('~')
    if p.startswith(home):
        p = '~' + p[len(home):]
    if len(p) <= max_len:
        return p
    parts = p.split('/')
    return '.../' + '/'.join(parts[-2:])

def format_tool(tc):
    name = tc.get('name', '?')
    inp = tc.get('input', {})
    tid = tc.get('id', '')
    result = tool_results.get(tid, {})
    err_marker = ' **ERR**' if result.get('is_error') else ''

    if name == 'Read':
        fp = shorten_path(inp.get('file_path', '?'))
        offset = inp.get('offset', '')
        limit = inp.get('limit', '')
        range_str = ''
        if offset or limit:
            range_str = f' (L{offset or 1}'
            if limit:
                range_str += f'-{(offset or 1) + limit}'
            range_str += ')'
        return f'📖 Read `{fp}`{range_str}{err_marker}'
    elif name == 'Edit':
        fp = shorten_path(inp.get('file_path', '?'))
        old_len = len(inp.get('old_string', ''))
        new_len = len(inp.get('new_string', ''))
        replace_all = inp.get('replace_all', False)
        ra = ' (all)' if replace_all else ''
        return f'✏️ Edit `{fp}` (-{old_len}/+{new_len} chars){ra}{err_marker}'
    elif name == 'Write':
        fp = shorten_path(inp.get('file_path', '?'))
        content_len = len(inp.get('content', ''))
        return f'📝 Write `{fp}` ({content_len} chars){err_marker}'
    elif name == 'Bash':
        cmd = inp.get('command', '?')
        desc = inp.get('description', '')
        bg = ' [bg]' if inp.get('run_in_background') else ''
        if desc:
            return f'⚡ Bash: {desc}{bg}{err_marker}'
        if len(cmd) > 80:
            cmd = cmd[:77] + '...'
        return f'⚡ `{cmd}`{bg}{err_marker}'
    elif name == 'Grep':
        pattern = inp.get('pattern', '?')
        path = shorten_path(inp.get('path', '.'))
        mode = inp.get('output_mode', 'files')
        return f'🔍 Grep `{pattern}` in `{path}` ({mode}){err_marker}'
    elif name == 'Glob':
        pattern = inp.get('pattern', '?')
        path = shorten_path(inp.get('path', '.'))
        return f'📂 Glob `{pattern}` in `{path}`{err_marker}'
    elif name == 'Agent':
        desc = inp.get('description', inp.get('prompt', '?')[:60])
        atype = inp.get('subagent_type', 'general')
        bg = ' [bg]' if inp.get('run_in_background') else ''
        return f'🤖 Agent({atype}): {desc}{bg}{err_marker}'
    elif name == 'WebFetch':
        url = inp.get('url', '?')
        if len(url) > 60:
            url = url[:57] + '...'
        return f'🌐 Fetch `{url}`{err_marker}'
    elif name == 'WebSearch':
        query = inp.get('query', '?')
        return f'🔎 Search: {query}{err_marker}'
    elif name == 'Skill':
        skill = inp.get('skill', '?')
        return f'⚙️ Skill: /{skill}{err_marker}'
    elif name == 'TaskCreate':
        subj = inp.get('subject', '?')
        return f'📋 TaskCreate: {subj}{err_marker}'
    elif name == 'TaskUpdate':
        ttid = inp.get('taskId', '?')
        status = inp.get('status', '')
        return f'📋 TaskUpdate #{ttid} → {status}{err_marker}'
    elif name == 'SendMessage':
        to = inp.get('to', '?')
        summary = inp.get('summary', '')
        return f'💬 Msg → {to}: {summary}{err_marker}'
    elif name.startswith('mcp__'):
        short_name = name.replace('mcp__', '').replace('__', '.')
        detail_keys = ['q', 'query', 'documentId', 'spreadsheetId', 'fileId', 'calendarId', 'messageId']
        detail = ''
        for k in detail_keys:
            if k in inp:
                detail = f' ({k}={str(inp[k])[:40]})'
                break
        return f'🔌 {short_name}{detail}{err_marker}'
    else:
        return f'🔧 {name}{err_marker}'

activity_lines = [format_tool(tc) for tc in tool_calls]

output = {
    'user_prompt': user_prompt,
    'activity': '\n'.join(activity_lines),
    'tool_count': len(tool_calls),
}
print(json.dumps(output))
PYEOF
  TURN_DATA=$(TRANSCRIPT="$TRANSCRIPT_PATH" python3 "$PY_SCRIPT" 2>/dev/null || true)
  rm -f "$PY_SCRIPT"
fi

# Parse the Python output
USER_PROMPT=""
ACTIVITY=""
TOOL_COUNT=0
if [ -n "$TURN_DATA" ]; then
  USER_PROMPT=$(echo "$TURN_DATA" | jq -r '.user_prompt // empty')
  ACTIVITY=$(echo "$TURN_DATA" | jq -r '.activity // empty')
  TOOL_COUNT=$(echo "$TURN_DATA" | jq -r '.tool_count // 0')
fi

# Redact sensitive info
LAST_ASSISTANT_MSG=$(echo "$LAST_ASSISTANT_MSG" | redact_sensitive)
USER_PROMPT=$(echo "$USER_PROMPT" | redact_sensitive)
ACTIVITY=$(echo "$ACTIVITY" | redact_sensitive)

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

# Build the full turn message with activity log
build_turn_message() {
  local prompt="$1"
  local activity="$2"
  local response="$3"
  local tool_count="$4"
  local msg=""

  msg="**Prompt:** ${prompt:-(none)}"

  if [ -n "$activity" ] && [ "$tool_count" -gt 0 ]; then
    msg="${msg}

**Activity** (${tool_count} tool calls):
${activity}"
  fi

  msg="${msg}

**Response:**
${response}"

  echo "$msg"
}

FULL_TURN_MSG=$(build_turn_message "$USER_PROMPT" "$ACTIVITY" "$LAST_ASSISTANT_MSG" "$TOOL_COUNT")

# --- Helper: post chunked text to a thread via webhook ---
post_to_thread() {
  local thread_id="$1"
  local text="$2"
  local remaining="$text"
  local chunk_num=0

  while [ -n "$remaining" ] && [ $chunk_num -lt 10 ]; do
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
  # --- Subsequent turn: post full turn into existing thread ---
  post_to_thread "$EXISTING_THREAD_ID" "$FULL_TURN_MSG"

else
  # --- First turn: new top-level embed + create thread ---

  TITLE=$(echo "$LAST_ASSISTANT_MSG" | grep -m1 -E '^#{1,4} ' | sed 's/^#\+ //' | head -c 256 || true)
  if [ -z "$TITLE" ]; then
    TITLE="${PROJECT} -- ${TIMESTAMP}"
  fi

  # For the embed, show response only (activity goes in thread)
  MAX_EMBED_DESC=3900
  RESPONSE_DISPLAY="$LAST_ASSISTANT_MSG"
  if [ ${#LAST_ASSISTANT_MSG} -gt $MAX_EMBED_DESC ]; then
    RESPONSE_DISPLAY="${LAST_ASSISTANT_MSG:0:$MAX_EMBED_DESC}..."
  fi

  FIELDS="[]"
  if [ -n "$USER_PROMPT" ]; then
    FIELDS=$(jq -n --arg prompt "$USER_PROMPT" '[{"name": "Prompt", "value": $prompt, "inline": false}]')
  fi
  if [ -n "$ACTIVITY" ] && [ "$TOOL_COUNT" -gt 0 ]; then
    # Truncate activity for embed field (1024 char limit)
    ACTIVITY_FIELD="$ACTIVITY"
    if [ ${#ACTIVITY_FIELD} -gt 1000 ]; then
      ACTIVITY_FIELD="${ACTIVITY_FIELD:0:997}..."
    fi
    FIELDS=$(echo "$FIELDS" | jq --arg act "$ACTIVITY_FIELD" --arg tc "$TOOL_COUNT" '. + [{"name": ("Activity (" + $tc + " tools)"), "value": $act, "inline": false}]')
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

          # Post the full turn (with activity) as the first thread message
          post_to_thread "$NEW_THREAD_ID" "$FULL_TURN_MSG"
        fi
      fi
    fi
  fi
fi

# Clean up stale thread files (older than 7 days)
find "$THREAD_STATE_DIR" -type f -mtime +7 -delete 2>/dev/null || true

exit 0
