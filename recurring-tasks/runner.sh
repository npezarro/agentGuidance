#!/usr/bin/env bash
# runner.sh — Shared task runner for recurring non-dev tasks.
# Reads a YAML-like task config, renders the prompt template, invokes Claude CLI,
# and handles locking, logging, timeouts, output capture, and Discord notifications.
#
# Usage: ./runner.sh <task-name> [--dry-run]
# Example: ./runner.sh job-search --dry-run
#
# Task configs live in tasks/<name>.conf (bash-sourceable key=value).
# Prompt templates live in prompts/<name>.md (with {{VAR}} placeholders).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_DIR="$SCRIPT_DIR/tasks"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
LOGS_DIR="$SCRIPT_DIR/logs"
OUTPUT_DIR="$SCRIPT_DIR/output"
LOCK_DIR="/tmp/recurring-tasks"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
DATE_TAG=$(date +%Y-%m-%d)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── Args ──────────────────────────────────────────────────────────────

TASK_NAME="${1:-}"
DRY_RUN=false
if [[ "${2:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

if [ -z "$TASK_NAME" ]; then
  echo "Usage: $0 <task-name> [--dry-run]"
  echo ""
  echo "Available tasks:"
  for f in "$TASKS_DIR"/*.conf; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .conf)
    desc=$(grep '^DESCRIPTION=' "$f" | head -1 | cut -d= -f2- | tr -d '"')
    echo "  $name — $desc"
  done
  exit 1
fi

TASK_CONF="$TASKS_DIR/${TASK_NAME}.conf"
PROMPT_FILE="$PROMPTS_DIR/${TASK_NAME}.md"

if [ ! -f "$TASK_CONF" ]; then
  echo "Error: Task config not found: $TASK_CONF" >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: Prompt template not found: $PROMPT_FILE" >&2
  exit 1
fi

# ── Load .env ─────────────────────────────────────────────────────────

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
  set +a
fi

# ── Load task config ──────────────────────────────────────────────────

# shellcheck disable=SC1090
source "$TASK_CONF"

# Defaults
TIMEOUT="${TIMEOUT:-1800}"
OUTPUT_MODE="${OUTPUT_MODE:-branch-pr}"
DISCORD_CHANNEL="${DISCORD_CHANNEL:-recurring-tasks}"
WORKING_DIR="${WORKING_DIR:-$SCRIPT_DIR}"
MAX_TURNS="${MAX_TURNS:-50}"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-}"
PERMISSION_MODE="${PERMISSION_MODE:-default}"

# ── Setup logging ─────────────────────────────────────────────────────

mkdir -p "$LOGS_DIR" "$OUTPUT_DIR" "$LOCK_DIR"

LOG_FILE="$LOGS_DIR/${TASK_NAME}-${DATE_TAG}.log"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [$TASK_NAME] $*" | tee -a "$LOG_FILE"
}

# ── Lock (flock-based, prevents concurrent runs of same task) ─────────

LOCKFILE="$LOCK_DIR/${TASK_NAME}.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
  log "SKIP: Another instance of '$TASK_NAME' is already running."
  exit 0
fi

log "START: Task '$TASK_NAME' (timeout: ${TIMEOUT}s, output: $OUTPUT_MODE)"

# ── Global concurrency check ─────────────────────────────────────────

MAX_CONCURRENT="${MAX_CONCURRENT_TASKS:-3}"
RUNNING=$(find "$LOCK_DIR" -name "*.lock" -newer /proc/1 -exec flock -n {} -c 'echo locked' \; 2>/dev/null | grep -c "locked" || echo 0)
# Note: this is approximate. If it matters, implement a proper counter.

# ── Render prompt template ────────────────────────────────────────────

PROMPT=$(cat "$PROMPT_FILE")
PROMPT="${PROMPT//\{\{DATE\}\}/$DATE_TAG}"
PROMPT="${PROMPT//\{\{TIMESTAMP\}\}/$TIMESTAMP}"
PROMPT="${PROMPT//\{\{WORKING_DIR\}\}/$WORKING_DIR}"
PROMPT="${PROMPT//\{\{OUTPUT_DIR\}\}/$OUTPUT_DIR}"
PROMPT="${PROMPT//\{\{TASK_NAME\}\}/$TASK_NAME}"

# Allow task-specific vars (TASK_VAR_* in the .conf)
while IFS='=' read -r key value; do
  if [[ "$key" == TASK_VAR_* ]]; then
    placeholder="${key#TASK_VAR_}"
    # Strip surrounding quotes from value
    value="${value%\"}"
    value="${value#\"}"
    PROMPT="${PROMPT//\{\{$placeholder\}\}/$value}"
  fi
done < <(grep '^TASK_VAR_' "$TASK_CONF" || true)

if [ "$DRY_RUN" = "true" ]; then
  log "DRY RUN -- prompt preview:"
  echo "$PROMPT"
  log "DRY RUN -- would invoke Claude in $WORKING_DIR with timeout ${TIMEOUT}s"
  exit 0
fi

# ── Pre-flight: verify Claude auth ────────────────────────────────────

AUTH_CHECK=$(echo "Say: OK" | "$CLAUDE_BIN" -p 2>&1 || true)
if echo "$AUTH_CHECK" | grep -qi "authentication_failed\|does not have access\|login again"; then
  log "FAIL: Claude auth failed. Run 'claude' interactively to re-auth."
  exit 1
fi

# ── Build Claude CLI args ─────────────────────────────────────────────

CLAUDE_ARGS=(-p --verbose --output-format stream-json)

if [ "$PERMISSION_MODE" = "scoped" ] && [ -n "$ALLOWED_TOOLS" ]; then
  # Use allowlist instead of --dangerously-skip-permissions
  for tool in $ALLOWED_TOOLS; do
    CLAUDE_ARGS+=(--allowedTools "$tool")
  done
else
  # Fallback: skip permissions for unattended execution
  # TODO: migrate all tasks to scoped permissions
  CLAUDE_ARGS+=(--dangerously-skip-permissions)
fi

if [ -n "${MAX_TURNS:-}" ]; then
  CLAUDE_ARGS+=(--max-turns "$MAX_TURNS")
fi

# ── Run Claude ────────────────────────────────────────────────────────

RUN_LOG="$LOGS_DIR/${TASK_NAME}-run-$(date -u +%Y%m%d-%H%M%S).log"
touch "$RUN_LOG" && chmod 600 "$RUN_LOG"

log "Invoking Claude CLI (max ${TIMEOUT}s)..."

cd "$WORKING_DIR"
timeout "$TIMEOUT" "$CLAUDE_BIN" \
  "${CLAUDE_ARGS[@]}" \
  <<< "$PROMPT" \
  > "$RUN_LOG" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  log "TIMEOUT: Task exceeded ${TIMEOUT}s limit"
fi

# ── Extract result ────────────────────────────────────────────────────

RESULT=$(grep -m1 '"type":"result"' "$RUN_LOG" 2>/dev/null \
  | jq -r '.result // "No result extracted"' 2>/dev/null \
  | head -c 3000 \
  || echo "No result extracted")

COST=$(grep '"type":"result"' "$RUN_LOG" 2>/dev/null \
  | jq -r 'select(.total_cost_usd) | "$\(.total_cost_usd | tostring | .[0:6])"' 2>/dev/null \
  | tail -1 \
  || echo "unknown")
[ -z "$COST" ] && COST="unknown"

# ── Save output metadata ─────────────────────────────────────────────

OUTPUT_META="$OUTPUT_DIR/${TASK_NAME}-${DATE_TAG}.json"
jq -n \
  --arg task "$TASK_NAME" \
  --arg date "$DATE_TAG" \
  --arg ts "$TIMESTAMP" \
  --argjson exit "$EXIT_CODE" \
  --arg cost "$COST" \
  --arg result "$RESULT" \
  --arg log_file "$RUN_LOG" \
  --arg output_mode "$OUTPUT_MODE" \
  '{task: $task, date: $date, started: $ts, exit_code: $exit, cost: $cost, result: $result, log_file: $log_file, output_mode: $output_mode}' \
  > "$OUTPUT_META"

# ── Post to Discord ───────────────────────────────────────────────────

DISCORD_WEBHOOK="${RECURRING_TASKS_WEBHOOK:-}"

post_discord() {
  local msg="$1"
  [ -z "$DISCORD_WEBHOOK" ] && return 0
  msg="${msg:0:1990}"
  local payload
  payload=$(jq -n --arg content "$msg" '{"username": "Recurring Tasks", "content": $content}')
  curl -s -X POST "$DISCORD_WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1 || true
}

if [ $EXIT_CODE -eq 0 ]; then
  log "DONE: Task '$TASK_NAME' completed (cost: $COST)"
  post_discord "**$TASK_NAME** completed (cost: $COST)

${RESULT:0:1800}"
else
  log "FAIL: Task '$TASK_NAME' exited with code $EXIT_CODE (cost: $COST)"
  post_discord "**$TASK_NAME** FAILED (exit: $EXIT_CODE, cost: $COST)

Check logs: recurring-tasks/logs/${TASK_NAME}-${DATE_TAG}.log"
fi

# ── Clean up old logs (keep last 30 per task) ─────────────────────────

ls -1t "$LOGS_DIR"/${TASK_NAME}-run-*.log 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true

# ── Clean up old output metadata (90 days) ────────────────────────────

find "$OUTPUT_DIR" -name "${TASK_NAME}-*.json" -mtime +90 -delete 2>/dev/null || true

log "END: Task '$TASK_NAME'"
