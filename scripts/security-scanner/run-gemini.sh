#!/usr/bin/env bash
# run-gemini.sh — Shadow Gemini version of security scanner.
# Runs the same scan prompt through Gemini CLI for quality comparison.
# Uses Gemini CLI (free GCA tier) instead of Claude.
#
# Differences from run.sh:
#   - Calls gemini instead of claude
#   - Separate lock file, log dir, state file
#   - No Claude usage gate (Gemini is free)
#   - Results logged to comparison JSONL
#   - Discord posts tagged [Gemini Shadow]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_TEMPLATE="$SCRIPT_DIR/scan-prompt.md"
LOGS_DIR="$SCRIPT_DIR/logs/gemini"
LOCKFILE="/tmp/security-scanner-gemini.lock"
STATE_FILE="$SCRIPT_DIR/gemini-state.json"
COMPARISON_LOG="$SCRIPT_DIR/logs/shadow-comparison.jsonl"

export GOOGLE_GENAI_USE_GCA=true
GEMINI_BIN="${GEMINI_BIN:-gemini}"
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
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [gemini] $*" | tee -a "$LOGS_DIR/runner.log"
}

# ── Lock (prevent overlapping runs) ──────────────────────────────────

exec 200>"$LOCKFILE"
if ! flock -n 200; then
  log "SKIP: Another Gemini security scan is already running"
  exit 0
fi

# Also skip if Claude scanner is running (avoid cloning conflicts in /tmp)
CLAUDE_LOCK="/tmp/security-scanner.lock"
if flock -n 201 201>"$CLAUDE_LOCK" 2>/dev/null; then
  flock -u 201
else
  log "SKIP: Claude security scanner active, avoiding /tmp conflict"
  exit 0
fi

# ── State management ─────────────────────────────────────────────────

RUN_NUMBER=1
if [ -f "$STATE_FILE" ]; then
  RUN_NUMBER=$(( $(jq -r '.run_number // 0' "$STATE_FILE" 2>/dev/null || echo 0) + 1 ))
fi

# ── Fetch public repos ───────────────────────────────────────────────

log "START: Gemini security scan #$RUN_NUMBER"

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

log "Spawning Gemini to scan $REPO_COUNT public repos..."

# ── Pre-flight: verify Gemini auth ───────────────────────────────────

AUTH_CHECK=$(echo "Say: OK" | "$GEMINI_BIN" --skip-trust -o stream-json -p "" 2>&1)
if echo "$AUTH_CHECK" | grep -qi "error\|auth.*fail\|GOOGLE_GENAI_USE_GCA"; then
  log "SKIP: Gemini auth failed"
  STATE_TMP="$STATE_FILE.tmp"
  jq -n --argjson num "$RUN_NUMBER" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{run_number: $num, last_run: $ts, last_exit_code: 1, last_error: "auth_failed"}' > "$STATE_TMP"
  mv "$STATE_TMP" "$STATE_FILE"
  exit 1
fi

# ── Run Gemini ───────────────────────────────────────────────────────

RUN_LOG="$LOGS_DIR/scan-${DATE_TAG}.log"
touch "$RUN_LOG" && chmod 600 "$RUN_LOG"
START_TIME=$(date +%s)

timeout 2700 "$GEMINI_BIN" \
  --skip-trust \
  -y \
  -o stream-json \
  -p "" \
  <<< "$PROMPT" \
  > "$RUN_LOG" 2>&1

EXIT_CODE=$?

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

if [ $EXIT_CODE -eq 124 ]; then
  log "TIMEOUT: Gemini scan exceeded 45 minute timeout"
fi

# ── Extract result ───────────────────────────────────────────────────

RESULT=$(grep '"role":"assistant"' "$RUN_LOG" 2>/dev/null \
  | python3 -c "
import json, sys
parts = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        c = d.get('content', '')
        if c: parts.append(c)
    except: pass
print('\n'.join(parts))
" 2>/dev/null | tail -c 16000 || echo "No result extracted")

STATS=$(grep '"type":"result"' "$RUN_LOG" 2>/dev/null | tail -1 || echo "{}")
TOTAL_TOKENS=$(echo "$STATS" | python3 -c "import json,sys; d=json.loads(sys.stdin.read().strip() or '{}'); print(d.get('stats',{}).get('total_tokens',0))" 2>/dev/null || echo "0")

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
  --argjson tokens "$TOTAL_TOKENS" \
  --argjson duration "$DURATION" \
  --argjson critical "$CRITICAL_COUNT" \
  --argjson high "$HIGH_COUNT" \
  --argjson total "$TOTAL_FINDINGS" \
  '{run_number: $num, last_run: $ts, last_exit_code: $exit, total_tokens: $tokens, duration_s: $duration, critical_findings: $critical, high_findings: $high, total_findings: $total}' \
  > "$STATE_TMP"
mv "$STATE_TMP" "$STATE_FILE"

# ── Log to comparison JSONL ──────────────────────────────────────────

jq -n \
  --arg agent "gemini" \
  --arg component "security-scanner" \
  --argjson run "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit_code "$EXIT_CODE" \
  --argjson duration "$DURATION" \
  --argjson tokens "$TOTAL_TOKENS" \
  --argjson critical "$CRITICAL_COUNT" \
  --argjson high "$HIGH_COUNT" \
  --argjson medium "$MEDIUM_COUNT" \
  --argjson low "$LOW_COUNT" \
  --argjson total "$TOTAL_FINDINGS" \
  --arg result_preview "${RESULT:0:1000}" \
  '{agent: $agent, component: $component, run: $run, timestamp: $ts, exit_code: $exit_code, duration_s: $duration, total_tokens: $tokens, critical: $critical, high: $high, medium: $medium, low: $low, total_findings: $total, result_preview: $result_preview}' \
  >> "$COMPARISON_LOG" 2>/dev/null || true

# ── Log result ───────────────────────────────────────────────────────

if [ $EXIT_CODE -eq 0 ]; then
  log "DONE: Gemini scan #$RUN_NUMBER — $TOTAL_FINDINGS findings ($CRITICAL_COUNT critical, $HIGH_COUNT high) — tokens=$TOTAL_TOKENS, ${DURATION}s"
else
  log "FAIL: Gemini scan #$RUN_NUMBER exited with code $EXIT_CODE"
fi

# ── Post to Discord (tagged as shadow) ───────────────────────────────

post_to_discord() {
  local webhook="$1" msg="$2"
  [ -z "$webhook" ] && return 0
  msg="${msg:0:1990}"
  local payload
  payload=$(jq -n --arg content "$msg" '{"username": "Security Scanner [Gemini]", "content": $content}')
  curl -s -X POST "$webhook" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1 || true
}

if [ $EXIT_CODE -eq 0 ] && [ "$TOTAL_FINDINGS" -gt 0 ]; then
  post_to_discord "$SECURITY_RISKS_WEBHOOK" "[Gemini Shadow] Security Scan #$RUN_NUMBER — $TOTAL_FINDINGS findings ($CRITICAL_COUNT critical, $HIGH_COUNT high, $MEDIUM_COUNT medium, $LOW_COUNT low)
tokens=$TOTAL_TOKENS, ${DURATION}s

${RESULT:0:1200}"
elif [ $EXIT_CODE -eq 0 ]; then
  post_to_discord "$SECURITY_RISKS_WEBHOOK" "[Gemini Shadow] Security Scan #$RUN_NUMBER — All clear ($REPO_COUNT repos, tokens=$TOTAL_TOKENS, ${DURATION}s)"
fi

# ── Clean up old logs (keep last 30) ─────────────────────────────────

ls -t "$LOGS_DIR"/scan-*.log 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true

log "Gemini security scan #$RUN_NUMBER complete."
