#!/usr/bin/env bash
# run-codex.sh — Shadow Codex/ChatGPT version of security scanner.
# Runs the same scan prompt through Codex CLI for quality comparison.
#
# Differences from run.sh:
#   - Calls codex instead of claude
#   - Separate lock file, log dir, state file
#   - No Claude usage gate (Codex uses ChatGPT Pro quota)
#   - Results logged to comparison JSONL
#   - Discord posts tagged [Codex Shadow]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_TEMPLATE="$SCRIPT_DIR/scan-prompt.md"
LOGS_DIR="$SCRIPT_DIR/logs/codex"
LOCKFILE="/tmp/security-scanner-codex.lock"
STATE_FILE="$SCRIPT_DIR/codex-state.json"
COMPARISON_LOG="$SCRIPT_DIR/logs/shadow-comparison.jsonl"

CODEX_BIN="${CODEX_BIN:-codex}"
DRY_RUN="${1:-}"
DATE_TAG=$(date -u +%Y-%m-%d)

# ── Load secrets from .env ────────────────────────────────────────────

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi

SECURITY_RISKS_WEBHOOK="${SECURITY_RISKS_WEBHOOK:-}"

# ── Logging ──────────────────────────────────────────────────────────

mkdir -p "$LOGS_DIR"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [codex] $*" | tee -a "$LOGS_DIR/runner.log"
}

# ── Lock (prevent overlapping runs) ──────────────────────────────────

exec 200>"$LOCKFILE"
if ! flock -n 200; then
  log "SKIP: Another Codex security scan is already running"
  exit 0
fi

# Also skip if Claude or Gemini scanner is running (avoid cloning conflicts in /tmp)
for sibling_lock in "/tmp/security-scanner.lock" "/tmp/security-scanner-gemini.lock"; do
  if ! flock -n 201 201>"$sibling_lock" 2>/dev/null; then
    log "SKIP: Sibling scanner active ($sibling_lock), avoiding /tmp conflict"
    exit 0
  fi
  flock -u 201
done

# ── State management ─────────────────────────────────────────────────

RUN_NUMBER=1
if [ -f "$STATE_FILE" ]; then
  RUN_NUMBER=$(( $(jq -r '.run_number // 0' "$STATE_FILE" 2>/dev/null || echo 0) + 1 ))
fi

# ── Fetch public repos ───────────────────────────────────────────────

log "START: Codex security scan #$RUN_NUMBER"

REPOS=$(gh repo list npezarro --visibility public --json name --jq '.[].name' 2>/dev/null)
if [ -z "$REPOS" ]; then
  log "FAIL: Could not fetch public repos from GitHub"
  exit 1
fi

REPO_COUNT=$(echo "$REPOS" | wc -l)
log "Found $REPO_COUNT public repos to scan"

REPO_LIST=""
for repo in $REPOS; do
  REPO_LIST="$REPO_LIST- https://github.com/npezarro/$repo
"
done

# ── Build prompt ─────────────────────────────────────────────────────

PROMPT=$(cat "$PROMPT_TEMPLATE")
PROMPT="${PROMPT//\{\{REPO_LIST\}\}/$REPO_LIST}"
PROMPT="${PROMPT//\{\{DATE\}\}/$DATE_TAG}"

if [ "$DRY_RUN" = "--dry-run" ]; then
  log "DRY RUN — would scan $REPO_COUNT repos"
  echo "$REPOS"
  exit 0
fi

log "Spawning Codex to scan $REPO_COUNT public repos..."

# ── Run Codex ────────────────────────────────────────────────────────

RUN_LOG="$LOGS_DIR/scan-${DATE_TAG}.log"
touch "$RUN_LOG" && chmod 600 "$RUN_LOG"
START_TIME=$(date +%s)

timeout 2700 "$CODEX_BIN" exec \
  --full-auto \
  "$PROMPT" \
  > "$RUN_LOG" 2>&1

EXIT_CODE=$?

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

if [ $EXIT_CODE -eq 124 ]; then
  log "TIMEOUT: Codex scan exceeded 45 minute timeout"
fi

# ── Extract result ───────────────────────────────────────────────────

RESULT=$(cat "$RUN_LOG" | tail -c 16000)

# ── Parse findings ──────────────────────────────────────────────────

CRITICAL_COUNT=$(echo "$RESULT" | grep -c 'SEVERITY: critical' || true)
HIGH_COUNT=$(echo "$RESULT" | grep -c 'SEVERITY: high' || true)
MEDIUM_COUNT=$(echo "$RESULT" | grep -c 'SEVERITY: medium' || true)
LOW_COUNT=$(echo "$RESULT" | grep -c 'SEVERITY: low' || true)
TOTAL_FINDINGS=$((CRITICAL_COUNT + HIGH_COUNT + MEDIUM_COUNT + LOW_COUNT))

# ── Update state ─────────────────────────────────────────────────────

STATE_TMP="$STATE_FILE.tmp"
jq -n \
  --argjson num "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit "$EXIT_CODE" \
  --argjson duration "$DURATION" \
  --argjson critical "$CRITICAL_COUNT" \
  --argjson high "$HIGH_COUNT" \
  --argjson total "$TOTAL_FINDINGS" \
  '{run_number: $num, last_run: $ts, last_exit_code: $exit, duration_s: $duration, critical_findings: $critical, high_findings: $high, total_findings: $total}' \
  > "$STATE_TMP"
mv "$STATE_TMP" "$STATE_FILE"

# ── Log to comparison JSONL ──────────────────────────────────────────

jq -n \
  --arg agent "codex" \
  --arg component "security-scanner" \
  --argjson run "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit_code "$EXIT_CODE" \
  --argjson duration "$DURATION" \
  --argjson critical "$CRITICAL_COUNT" \
  --argjson high "$HIGH_COUNT" \
  --argjson medium "$MEDIUM_COUNT" \
  --argjson low "$LOW_COUNT" \
  --argjson total "$TOTAL_FINDINGS" \
  --arg result_preview "${RESULT:0:1000}" \
  '{agent: $agent, component: $component, run: $run, timestamp: $ts, exit_code: $exit_code, duration_s: $duration, critical: $critical, high: $high, medium: $medium, low: $low, total_findings: $total, result_preview: $result_preview}' \
  >> "$COMPARISON_LOG" 2>/dev/null || true

# ── Log result ───────────────────────────────────────────────────────

if [ $EXIT_CODE -eq 0 ]; then
  log "DONE: Codex scan #$RUN_NUMBER — $TOTAL_FINDINGS findings ($CRITICAL_COUNT critical, $HIGH_COUNT high) — ${DURATION}s"
else
  log "FAIL: Codex scan #$RUN_NUMBER exited with code $EXIT_CODE"
fi

# ── Post to Discord (tagged as shadow) ───────────────────────────────

post_to_discord() {
  local webhook="$1" msg="$2"
  [ -z "$webhook" ] && return 0
  msg="${msg:0:1990}"
  local payload
  payload=$(jq -n --arg content "$msg" '{"username": "Security Scanner [Codex]", "content": $content}')
  curl -s -X POST "$webhook" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1 || true
}

if [ $EXIT_CODE -eq 0 ] && [ "$TOTAL_FINDINGS" -gt 0 ]; then
  post_to_discord "$SECURITY_RISKS_WEBHOOK" "[Codex Shadow] Security Scan #$RUN_NUMBER — $TOTAL_FINDINGS findings ($CRITICAL_COUNT critical, $HIGH_COUNT high, $MEDIUM_COUNT medium, $LOW_COUNT low)
${DURATION}s

${RESULT:0:1200}"
elif [ $EXIT_CODE -eq 0 ]; then
  post_to_discord "$SECURITY_RISKS_WEBHOOK" "[Codex Shadow] Security Scan #$RUN_NUMBER — All clear ($REPO_COUNT repos, ${DURATION}s)"
fi

# ── Clean up old logs (keep last 30) ─────────────────────────────────

ls -t "$LOGS_DIR"/scan-*.log 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true

log "Codex security scan #$RUN_NUMBER complete."
