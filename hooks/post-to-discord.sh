#!/bin/bash
# Post each Claude Code turn to Discord via the bot's /ingest endpoint.
# Triggered by the Stop hook event.
#
# The bot handles all Discord formatting, threading (#cli-interactions),
# and routing to #prompts and #logging. This script just extracts
# structured turn data from the transcript and sends it to /ingest.
#
# Rich logging:
#   - Extracts tool calls (Read, Edit, Bash, Grep, Glob, Write, Agent, etc.)
#     from the transcript and formats them as an activity log.

set -uo pipefail

# --- Credential Resolution (needed for env vars like INGEST_SECRET) ---
for envfile in "$HOME/.env" $HOME/discord-bot/.env; do
  if [ -f "$envfile" ]; then
    source "$envfile"
    break
  fi
done

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

# ── POST to bot event bus ─────────────────────────────────────────
# The bot handles all Discord formatting, threading, and posting to
# #cli-interactions, #prompts, and #logging via the /ingest endpoint.
#
# The health server binds to 127.0.0.1 on the VM, so we try local first
# (works when CLI runs on the VM), then fall back to SSH (local PC → VM).
INGEST_PORT="${HEALTH_PORT:-9090}"
INGEST_URL="http://127.0.0.1:${INGEST_PORT}/ingest"
VM_SSH_KEY="${VM_SSH_KEY:-$HOME/.ssh/vm_key}"
VM_HOST="${VM_HOST:-deploy-vm}"

INGEST_PAYLOAD=$(_EB_PROMPT="$USER_PROMPT" \
  _EB_ACTIVITY="$ACTIVITY" \
  _EB_TOOL_COUNT="$TOOL_COUNT" \
  _EB_RESPONSE="$LAST_ASSISTANT_MSG" \
  _EB_PROJECT="$PROJECT" \
  _EB_SESSION="$SESSION_ID" \
  _EB_CWD="$CWD" \
  python3 -c "
import json, os
payload = {
    'source': 'cli',
    'type': 'interaction',
    'content': {
        'user_prompt': os.environ.get('_EB_PROMPT', ''),
        'activity': os.environ.get('_EB_ACTIVITY', ''),
        'tool_count': int(os.environ.get('_EB_TOOL_COUNT', '0')),
        'response': os.environ.get('_EB_RESPONSE', '')[:8000]
    },
    'metadata': {
        'project': os.environ.get('_EB_PROJECT', ''),
        'session_id': os.environ.get('_EB_SESSION', ''),
        'cwd': os.environ.get('_EB_CWD', '')
    }
}
print(json.dumps(payload))
" 2>/dev/null) || true

if [ -n "$INGEST_PAYLOAD" ]; then
  _AUTH_HEADER=""
  if [ -n "${INGEST_SECRET:-}" ]; then
    _AUTH_HEADER="Authorization: Bearer ${INGEST_SECRET}"
  fi

  # Try localhost first (works when running on the VM itself)
  _INGEST_OK=0
  curl -s -X POST "$INGEST_URL" \
    -H "Content-Type: application/json" \
    ${_AUTH_HEADER:+-H "$_AUTH_HEADER"} \
    -d "$INGEST_PAYLOAD" \
    --max-time 3 -o /dev/null 2>/dev/null && _INGEST_OK=1

  # If local failed and SSH key exists, relay via SSH to the VM
  # Pipes payload via stdin to avoid shell-escaping issues with arbitrary content
  if [ "$_INGEST_OK" -eq 0 ] && [ -f "$VM_SSH_KEY" ]; then
    echo "$INGEST_PAYLOAD" | ssh -i "$VM_SSH_KEY" -o StrictHostKeyChecking=no \
      -o ConnectTimeout=5 -o BatchMode=yes "$VM_HOST" \
      "curl -s -X POST 'http://127.0.0.1:${INGEST_PORT}/ingest' \
        -H 'Content-Type: application/json' \
        --max-time 5 -o /dev/null -d @-" 2>/dev/null || true
  fi
fi

exit 0
