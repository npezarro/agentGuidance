#!/bin/bash
# Post each Claude Code turn as a private WordPress post
# Triggered by the Stop hook event

set -euo pipefail

# --- Credential Resolution ---
# Priority: env vars (set via settings.json "env" block) > .env files > exit silently
if [ -z "${WP_USER:-}" ] || [ -z "${WP_APP_PASSWORD:-}" ]; then
  for envfile in "$HOME/.env" $HOME/.env; do
    if [ -f "$envfile" ]; then
      source "$envfile"
      break
    fi
  done
fi

if [ -z "${WP_USER:-}" ] || [ -z "${WP_APP_PASSWORD:-}" ]; then
  exit 0  # No credentials available — skip silently
fi

# --- Markdown to HTML ---
# Convert markdown to proper HTML for WordPress rendering.
# Uses python-markdown if available; falls back to basic sed conversion.
md_to_html() {
  local input
  input=$(cat)
  converted=$(echo "$input" | python3 -c "
import sys
text = sys.stdin.read()
try:
    import markdown
    print(markdown.markdown(text, extensions=['tables', 'fenced_code']))
except ImportError:
    import re, html as h
    t = h.escape(text)
    # fenced code blocks
    t = re.sub(r'\`\`\`(\w*)\n(.*?)\`\`\`', lambda m: '<pre><code>' + m.group(2) + '</code></pre>', t, flags=re.S)
    # headings
    t = re.sub(r'^#### (.+)$', r'<h4>\1</h4>', t, flags=re.M)
    t = re.sub(r'^### (.+)$', r'<h3>\1</h3>', t, flags=re.M)
    t = re.sub(r'^## (.+)$', r'<h2>\1</h2>', t, flags=re.M)
    t = re.sub(r'^# (.+)$', r'<h1>\1</h1>', t, flags=re.M)
    # bold and italic
    t = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', t)
    t = re.sub(r'\*(.+?)\*', r'<em>\1</em>', t)
    # inline code
    t = re.sub(r'\`([^\`]+)\`', r'<code>\1</code>', t)
    # unordered lists
    t = re.sub(r'((?:^- .+\n?)+)', lambda m: '<ul>\n' + re.sub(r'^- (.+)$', r'<li>\1</li>', m.group(0), flags=re.M) + '</ul>\n', t, flags=re.M)
    # horizontal rules
    t = re.sub(r'^---+$', '<hr />', t, flags=re.M)
    # links
    t = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href=\"\2\">\1</a>', t)
    # paragraphs (double newlines)
    t = re.sub(r'\n\n+', '</p>\n<p>', t.strip())
    t = '<p>' + t + '</p>'
    # clean up empty paragraphs and paragraphs wrapping block elements
    t = re.sub(r'<p>\s*</p>', '', t)
    t = re.sub(r'<p>\s*(<h[1-4])', r'\1', t)
    t = re.sub(r'(</h[1-4]>)\s*</p>', r'\1', t)
    t = re.sub(r'<p>\s*(<ul>)', r'\1', t)
    t = re.sub(r'(</ul>)\s*</p>', r'\1', t)
    t = re.sub(r'<p>\s*(<pre>)', r'\1', t)
    t = re.sub(r'(</pre>)\s*</p>', r'\1', t)
    t = re.sub(r'<p>\s*(<hr)', r'\1', t)
    t = re.sub(r'(<hr />)\s*</p>', r'\1', t)
    print(t)
" 2>/dev/null) || converted="$input"
  echo "$converted"
}

WP_SITE="https://YOUR_DOMAIN"
WP_API="${WP_SITE}/wp-json/wp/v2/posts"
AUTH=$(echo -n "${WP_USER}:${WP_APP_PASSWORD}" | base64)

# --- Redaction ---
# Scrub sensitive information from text before posting to WordPress.
# Defense-in-depth: agent.md also instructs Claude to self-censor,
# but this catches anything that slips through.
redact_sensitive() {
  sed -E \
    -e 's/[A-Za-z0-9]{4} [A-Za-z0-9]{4} [A-Za-z0-9]{4} [A-Za-z0-9]{4} [A-Za-z0-9]{4} [A-Za-z0-9]{4}/[REDACTED_APP_PASSWORD]/g' \
    -e 's/ghp_[A-Za-z0-9]{36,}/[REDACTED_GITHUB_TOKEN]/g' \
    -e 's/github_pat_[A-Za-z0-9_]{40,}/[REDACTED_GITHUB_PAT]/g' \
    -e 's/sk-proj-[A-Za-z0-9_-]{40,}/[REDACTED_API_KEY]/g' \
    -e 's/sk-[A-Za-z0-9]{20,}/[REDACTED_API_KEY]/g' \
    -e 's/key-[A-Za-z0-9]{20,}/[REDACTED_API_KEY]/g' \
    -e 's/Bearer [A-Za-z0-9._-]{20,}/Bearer [REDACTED_BEARER]/g' \
    -e 's/(Authorization: Basic )[A-Za-z0-9+\/=]{10,}/\1[REDACTED_AUTH]/g' \
    -e 's/(SECRET|_SECRET|CLIENT_SECRET|TOKEN_ENCRYPTION_KEY|API_KEY|OPENAI_API_KEY|SMTP_PASS|APP_PASSWORD|WP_APP_PASSWORD)=[^ "'\'']+/\1=[REDACTED]/g' \
    -e 's/(PASSWORD|_PASS|_PASSWORD|CREDENTIAL|_CREDENTIAL)=[^ "'\'']+/\1=[REDACTED]/g' \
    -e 's|https?://[^:@ ]+:[^@ ]+@|https://[REDACTED_CREDS]@|g' \
    -e 's/-----BEGIN[A-Z ]*PRIVATE KEY-----[^-]*-----END[A-Z ]*PRIVATE KEY-----/[REDACTED_PRIVATE_KEY]/g' \
    -e 's/\b(10\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))\b/[REDACTED_IP]/g' \
    -e 's/\b(192\.168\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))\b/[REDACTED_IP]/g' \
    -e 's/\b(172\.(1[6-9]|2[0-9]|3[01])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))\b/[REDACTED_IP]/g'
}

# Read hook input from stdin
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
LAST_ASSISTANT_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')

# Skip if no transcript or no assistant message
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] || [ -z "$LAST_ASSISTANT_MSG" ]; then
  exit 0
fi

# Extract the last user prompt from transcript
# User messages have type="user" and message.content is a string (not tool_result arrays)
# Use jq --slurp with reverse to handle files with/without trailing newlines
USER_PROMPT=$(jq -rs '[.[] | select(.type == "user" and (.message.content | type == "string"))] | last | .message.content // empty' "$TRANSCRIPT_PATH" 2>/dev/null)

# Skip if we couldn't find a user prompt
if [ -z "$USER_PROMPT" ]; then
  exit 0
fi

# Redact sensitive information from both prompt and response
USER_PROMPT=$(echo "$USER_PROMPT" | redact_sensitive)
LAST_ASSISTANT_MSG=$(echo "$LAST_ASSISTANT_MSG" | redact_sensitive)

# Summarize long prompts — keep first line + truncate body
PROMPT_LEN=${#USER_PROMPT}
PROMPT_DISPLAY="$USER_PROMPT"
if [ "$PROMPT_LEN" -gt 300 ]; then
  FIRST_LINE=$(echo "$USER_PROMPT" | head -1 | cut -c1-120)
  PROMPT_DISPLAY="${FIRST_LINE}...

<em>[Full prompt truncated — ${PROMPT_LEN} chars. See transcript for complete text.]</em>"
fi

# Summarize long assistant responses — keep first ~2000 chars
RESPONSE_LEN=${#LAST_ASSISTANT_MSG}
RESPONSE_DISPLAY="$LAST_ASSISTANT_MSG"
if [ "$RESPONSE_LEN" -gt 2000 ]; then
  RESPONSE_DISPLAY=$(echo "$LAST_ASSISTANT_MSG" | head -c 2000)
  RESPONSE_DISPLAY="${RESPONSE_DISPLAY}...

<em>[Response truncated — ${RESPONSE_LEN} chars total. See transcript for complete output.]</em>"
fi

# Get working directory and extract project name for narrative framing
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
PROJECT=$(basename "$CWD")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DATE_HUMAN=$(date '+%B %-d, %Y')

# Build the title from the response content — since the response IS the blog post.
# Priority: first markdown heading > first sentence > project + date fallback.
RESPONSE_HEADING=$(echo "$LAST_ASSISTANT_MSG" | grep -m1 -E '^#{1,4} ' | sed 's/^#\+ //')
if [ -n "$RESPONSE_HEADING" ]; then
  TITLE=$(echo "$RESPONSE_HEADING" | cut -c1-70)
else
  RESPONSE_FIRST=$(echo "$LAST_ASSISTANT_MSG" | grep -m1 -E '.{10,}' | sed 's/^[[:space:]]*//' | cut -c1-80 | sed 's/[[:space:]][^[:space:]]*$//' | head -c 70)
  if [ -n "$RESPONSE_FIRST" ] && [ "$(echo "$RESPONSE_FIRST" | wc -w | tr -d ' ')" -ge 3 ]; then
    TITLE="$RESPONSE_FIRST"
    if [ ${#TITLE} -ge 68 ]; then
      TITLE="${TITLE}..."
    fi
  else
    TITLE="${PROJECT} — $(date '+%b %-d, %Y')"
  fi
fi

# --- Convert markdown to HTML ---
RESPONSE_HTML=$(echo "$RESPONSE_DISPLAY" | md_to_html)

# --- "Previously on..." recap ---
# Fetch the last 3 private posts to build a recap section, like a TV series cold open.
# Fails silently — if the API is unreachable, we just skip the recap.
RECAP_HTML=""
RECENT_POSTS=$(curl -s --max-time 5 \
  -H "Authorization: Basic ${AUTH}" \
  "${WP_API}?per_page=3&status=private&orderby=date&order=desc" 2>/dev/null)

if [ -n "$RECENT_POSTS" ] && echo "$RECENT_POSTS" | jq -e '.[0].id' &>/dev/null; then
  RECAP_ITEMS=$(echo "$RECENT_POSTS" | jq -r '.[] | "<li><a href=\"" + .link + "\">" + .title.rendered + "</a></li>"' 2>/dev/null)
  if [ -n "$RECAP_ITEMS" ]; then
    RECAP_HTML="<div style=\"background:#f7f7f7; border-left:4px solid #999; padding:12px 16px; margin-bottom:24px;\">
<p><strong>Previously on&hellip;</strong></p>
<ul style=\"margin:8px 0 0 0;\">
${RECAP_ITEMS}
</ul>
</div>

"
  fi
fi

# --- Build post content ---
# The response IS the blog post. No template wrapper — just recap, content, and metadata.
CONTENT="${RECAP_HTML}${RESPONSE_HTML}

<hr />
<p style='color:#888; font-size:0.9em;'>Logged on ${DATE_HUMAN} at ${TIMESTAMP} &mdash; Session <code>${SESSION_ID}</code> in <code>${CWD}</code></p>"

# Create the WordPress post (private, filed under "Claude Journals" category)
PAYLOAD=$(jq -n \
  --arg title "$TITLE" \
  --arg content "$CONTENT" \
  --arg status "private" \
  '{title: $title, content: $content, status: $status, categories: [16]}')

curl -s -X POST "$WP_API" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic ${AUTH}" \
  -d "$PAYLOAD" \
  -o /dev/null \
  -w "" \
  --max-time 10 2>/dev/null || true

exit 0
