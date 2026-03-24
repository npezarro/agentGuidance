#!/bin/bash
# Search WordPress posts for context.
# Usage: search-wp-posts.sh [search_query] [max_results]
# Primary method: SSH to VM + WP-CLI (site runs on the VM)
# Fallback: WP REST API with Basic Auth
#
# Returns posts as a formatted list: Date | Title | Excerpt

set -euo pipefail

QUERY="${1:-}"
MAX="${2:-10}"

# Infrastructure config — sourced from environment or ~/.config/agent-guidance/.env
AG_ENV_FILE="${AG_ENV_FILE:-$HOME/.config/agent-guidance/.env}"
if [ -f "$AG_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$AG_ENV_FILE"
fi

VM_HOST="${AG_VM_HOST:?AG_VM_HOST not set — see .env.example}"
VM_USER="${AG_VM_USER:?AG_VM_USER not set — see .env.example}"
SSH_KEY="${AG_SSH_KEY:-$HOME/.ssh/vm_key}"
WP_PATH="${AG_WP_PATH:-/var/www/html}"

# --- Try SSH + WP-CLI first ---
try_wp_cli() {
  local search_flag=""
  if [ -n "$QUERY" ]; then
    search_flag="--s='${QUERY}'"
  fi

  ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    "${VM_USER}@${VM_HOST}" "
    cd ${WP_PATH} 2>/dev/null || true
    wp post list \
      --post_status=private,publish \
      --posts_per_page=${MAX} \
      --orderby=date \
      --order=DESC \
      ${search_flag} \
      --fields=ID,post_date,post_title \
      --format=table 2>/dev/null
  " 2>/dev/null
}

# --- Fallback: WP REST API ---
try_rest_api() {
  # Resolve credentials
  if [ -z "${WP_USER:-}" ] || [ -z "${WP_APP_PASSWORD:-}" ]; then
    if [ -f "$HOME/.env" ]; then
      while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        value="${value%\"}" ; value="${value#\"}"
        value="${value%\'}" ; value="${value#\'}"
        key="$(echo "$key" | xargs)"
        export "$key=$value"
      done < "$HOME/.env"
    fi
  fi

  if [ -z "${WP_USER:-}" ] || [ -z "${WP_APP_PASSWORD:-}" ]; then
    return 1
  fi

  local WP_SITE="${AG_WP_SITE:-https://${AG_VM_HOST}}"
  local WP_API="${WP_SITE}/wp-json/wp/v2/posts"
  local AUTH
  AUTH=$(echo -n "${WP_USER}:${WP_APP_PASSWORD}" | base64)

  local PARAMS="per_page=${MAX}&status=private,publish&orderby=date&order=desc&_fields=id,title,date,excerpt,link"
  if [ -n "$QUERY" ]; then
    local ENCODED_QUERY
    ENCODED_QUERY=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$QUERY")
    PARAMS="${PARAMS}&search=${ENCODED_QUERY}"
  fi

  local RESPONSE
  RESPONSE=$(curl -s --max-time 10 \
    -H "Authorization: Basic ${AUTH}" \
    "${WP_API}?${PARAMS}" 2>/dev/null)

  if [ -z "$RESPONSE" ] || ! echo "$RESPONSE" | jq -e '.[0].id' &>/dev/null; then
    echo "No posts found."
    return 0
  fi

  # Format as readable output
  echo "$RESPONSE" | jq -r '.[] |
    "---",
    "Date: \(.date | split("T")[0])",
    "Title: \(.title.rendered)",
    "Link: \(.link)",
    "Excerpt: \(.excerpt.rendered | gsub("<[^>]*>"; "") | gsub("\\n"; " ") | gsub("\\s+"; " ") | .[0:200])",
    ""'
}

# Try WP-CLI via SSH first, fall back to REST API
echo "=== WordPress Posts $([ -n "$QUERY" ] && echo "(search: $QUERY)" || echo "(recent)") ==="
echo ""

if result=$(try_wp_cli 2>/dev/null) && [ -n "$result" ]; then
  echo "$result"
elif result=$(try_rest_api 2>/dev/null) && [ -n "$result" ]; then
  echo "$result"
else
  echo "Could not connect to WordPress. Tried SSH+WP-CLI and REST API."
  echo "Check ~/.config/agent-guidance/.env or see .env.example for required variables."
  exit 1
fi
