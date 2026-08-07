#!/bin/bash
# Save each Claude Code session closeout as a .md file in ~/repos/wordpressPosts
# Triggered by the Stop hook event
# Writes to the local wordpressPosts git repo for review; does NOT post to WordPress directly.

set -euo pipefail

REPO_DIR="${HOME}/repos/wordpressPosts"
SCAN_SCRIPT="${HOME}/repos/privateContext/security-scan.sh"
REDACT_SCRIPT="${HOME}/repos/privateContext/redact-identifiers.sh"
HOOK_LOG="${HOME}/.cache/wp-posts/hook.log"

# Skip if repo doesn't exist
if [ ! -d "$REPO_DIR/.git" ]; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  exit 0
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
    -e 's/(Authorization: Basic )[A-Za-z0-9+\/=]{10,}/\1[REDACTED_AUTH]/g' \
    -e 's/(SECRET|_SECRET|CLIENT_SECRET|TOKEN_ENCRYPTION_KEY|API_KEY|OPENAI_API_KEY|SMTP_PASS|APP_PASSWORD|WP_APP_PASSWORD)=[^ "'\'']+/\1=[REDACTED]/g' \
    -e 's/(PASSWORD|_PASS|_PASSWORD|CREDENTIAL|_CREDENTIAL)=[^ "'\'']+/\1=[REDACTED]/g' \
    -e 's|https?://[^:@ ]+:[^@ ]+@|https://[REDACTED_CREDS]@|g' \
    -e 's/-----BEGIN[A-Z ]*PRIVATE KEY-----[^-]*-----END[A-Z ]*PRIVATE KEY-----/[REDACTED_PRIVATE_KEY]/g' \
    -e 's/\b(10\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))\b/[REDACTED_IP]/g' \
    -e 's/\b(192\.168\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))\b/[REDACTED_IP]/g' \
    -e 's/\b(172\.(1[6-9]|2[0-9]|3[01])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))\b/[REDACTED_IP]/g'
}

# Secrets are only half the job. These posts are published to a public blog, so
# they also have to lose the non-secret identifiers that reveal infrastructure
# layout and private repo names -- the same list the commit gate enforces.
# Without this pass every post naming the VM or a private repo is written to
# disk already unable to be committed (2026-08-07: 29 had piled up that way).
redact_all() {
  if [ -x "$REDACT_SCRIPT" ]; then
    redact_sensitive | "$REDACT_SCRIPT" --repo "$REPO_DIR"
  else
    redact_sensitive
  fi
}

log_hook() {
  mkdir -p "$(dirname "$HOOK_LOG")"
  echo "$*" >> "$HOOK_LOG"
}

# Read hook input from stdin.
# Register the cleanup trap BEFORE mktemp (deferred expansion via single
# quotes) so no exit path after temp file creation can leak it.
INPUT_FILE=""
trap 'rm -f "$INPUT_FILE"' EXIT
INPUT_FILE=$(mktemp)
cat > "$INPUT_FILE"
SESSION_ID=$(jq -r '.session_id // empty' < "$INPUT_FILE")
TRANSCRIPT_PATH=$(jq -r '.transcript_path // empty' < "$INPUT_FILE")
LAST_ASSISTANT_MSG=$(jq -r '.last_assistant_message // empty' < "$INPUT_FILE")

# Skip if no transcript or no assistant message
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] || [ -z "$LAST_ASSISTANT_MSG" ]; then
  exit 0
fi

# --- Deduplication ---
WP_CACHE_DIR="$HOME/.cache/wp-posts"
mkdir -p "$WP_CACHE_DIR"
find "$WP_CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null || true

if [ -n "$SESSION_ID" ] && [ -f "$WP_CACHE_DIR/session-${SESSION_ID}" ]; then
  exit 0
fi

CONTENT_HASH=$(printf '%s' "$LAST_ASSISTANT_MSG" | sha256sum | cut -d' ' -f1)
if [ -f "$WP_CACHE_DIR/hash-${CONTENT_HASH}" ]; then
  exit 0
fi

# Extract the last user prompt from transcript
USER_PROMPT=$(jq -rs '[.[] | select(.type == "user" and (.message.content | type == "string"))] | last | .message.content // empty' "$TRANSCRIPT_PATH" 2>/dev/null)

if [ -z "$USER_PROMPT" ]; then
  exit 0
fi

# Redact sensitive information
if [ ! -x "$REDACT_SCRIPT" ]; then
  log_hook "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $REDACT_SCRIPT missing; identifier redaction skipped"
fi
USER_PROMPT=$(echo "$USER_PROMPT" | redact_all)
LAST_ASSISTANT_MSG=$(echo "$LAST_ASSISTANT_MSG" | redact_all)

# Get working directory and extract project name.
# The raw cwd carries the operator's WSL and Windows usernames into the
# frontmatter of every published post, so anchor it to ~ before use.
CWD=$(jq -r '.cwd // "unknown"' < "$INPUT_FILE")
CWD=$(printf '%s' "$CWD" | sed -e "s|^${HOME}|~|" -e 's|^/mnt/c/Users/[^/]*|~|' | redact_all)
PROJECT=$(basename "$CWD")
# basename('~') is the home dir itself, which is not a project.
[ "$PROJECT" = "~" ] && PROJECT="home"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DATE_SLUG=$(date '+%Y-%m-%d')

# Build the title from the response content
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

# Build a filesystem-safe slug from the title
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-80)
FILENAME="${DATE_SLUG}-${SLUG}.md"
FILEPATH="${REPO_DIR}/${FILENAME}"

# Handle filename collisions
COUNTER=1
while [ -f "$FILEPATH" ]; do
  FILENAME="${DATE_SLUG}-${SLUG}-${COUNTER}.md"
  FILEPATH="${REPO_DIR}/${FILENAME}"
  COUNTER=$((COUNTER + 1))
done

# Build the markdown file with frontmatter
cat > "$FILEPATH" <<MDEOF
---
title: "${TITLE//\"/\\\"}"
date: ${TIMESTAMP}
session_id: ${SESSION_ID}
project: ${PROJECT}
cwd: ${CWD}
---

${LAST_ASSISTANT_MSG}
MDEOF

# Commit and push
cd "$REPO_DIR"

# Self-check before committing. If redaction missed something the gate blocks,
# the commit below fails -- and the old code discarded that failure, so the
# backlog grew invisibly. Name the gap instead: it means a pattern exists in
# sensitive-identifiers.md with no Redaction Replacements entry.
if [ -x "$SCAN_SCRIPT" ] && ! SCAN_OUT=$("$SCAN_SCRIPT" --file "$FILEPATH" 2>&1); then
  log_hook "[$TIMESTAMP] STILL DIRTY after redaction: $FILENAME"
  log_hook "$(echo "$SCAN_OUT" | sed 's/^/    /')"
  log_hook "    fix: add a Redaction Replacements entry in sensitive-identifiers.md"
  echo "save-to-wp-repo: $FILENAME still trips the secret gate. See $HOOK_LOG" >&2
fi

# Commit this path only. `git add` plus a path-limited `git commit` builds a
# temporary index, so a concurrent session sharing this checkout neither has
# its staged work swept into this commit nor blocks this one with its own
# unredacted files. Never commit the whole index here.
git add -- "$FILENAME" 2>/dev/null || true
if COMMIT_OUT=$(git commit -m "Add: ${TITLE}" --no-gpg-sign -- "$FILENAME" 2>&1); then
  if ! PUSH_OUT=$(git push origin HEAD 2>&1); then
    log_hook "[$TIMESTAMP] push failed after committing $FILENAME:"
    log_hook "$(echo "$PUSH_OUT" | sed 's/^/    /')"
  fi
else
  # Leave the file on disk for repair, but take it back out of the shared
  # index so it cannot ride along on someone else's commit.
  git restore --staged -- "$FILENAME" 2>/dev/null || true
  log_hook "[$TIMESTAMP] commit failed for $FILENAME:"
  log_hook "$(echo "$COMMIT_OUT" | sed 's/^/    /')"
  echo "save-to-wp-repo: commit failed for $FILENAME. See $HOOK_LOG" >&2
fi

# Record in dedup cache
[ -n "$SESSION_ID" ] && echo "$TIMESTAMP" > "$WP_CACHE_DIR/session-${SESSION_ID}"
echo "$TIMESTAMP" > "$WP_CACHE_DIR/hash-${CONTENT_HASH}"

exit 0
