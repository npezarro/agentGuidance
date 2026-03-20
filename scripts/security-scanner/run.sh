#!/usr/bin/env bash
# run.sh — Daily security scanner for public GitHub repositories.
# Clones all public repos, spawns Claude to scan for secrets/sensitive data,
# posts findings to Discord #security-risks, and emails critical findings.
#
# Usage: ./run.sh [--dry-run]
# Requires: claude, gh, jq, curl

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_TEMPLATE="$SCRIPT_DIR/scan-prompt.md"
LOGS_DIR="$SCRIPT_DIR/logs"
LOCKFILE="/tmp/security-scanner.lock"
STATE_FILE="$SCRIPT_DIR/state.json"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
DRY_RUN="${1:-}"
DATE_TAG=$(date -u +%Y-%m-%d)

# ── Load secrets from .env ────────────────────────────────────────────

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

SECURITY_RISKS_WEBHOOK="${SECURITY_RISKS_WEBHOOK:-}"
GMAIL_ALERT_ENABLED="${GMAIL_ALERT_ENABLED:-true}"
ALERT_EMAIL="${ALERT_EMAIL:?ALERT_EMAIL must be set in .env}"

# ── Logging ──────────────────────────────────────────────────────────

mkdir -p "$LOGS_DIR"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$LOGS_DIR/runner.log"
}

# ── Lock (prevent overlapping runs) ──────────────────────────────────

exec 200>"$LOCKFILE"
if ! flock -n 200; then
  log "SKIP: Another security scan is already running"
  exit 0
fi

# ── State management ─────────────────────────────────────────────────

RUN_NUMBER=1
if [ -f "$STATE_FILE" ]; then
  RUN_NUMBER=$(( $(jq -r '.run_number // 0' "$STATE_FILE" 2>/dev/null || echo 0) + 1 ))
fi

# ── Fetch public repos ───────────────────────────────────────────────

log "START: Security scan #$RUN_NUMBER"

REPOS=$(gh repo list npezarro --visibility public --json name --jq '.[].name' 2>/dev/null)
if [ -z "$REPOS" ]; then
  log "FAIL: Could not fetch public repos from GitHub"
  exit 1
fi

REPO_COUNT=$(echo "$REPOS" | wc -l)
log "Found $REPO_COUNT public repos to scan"

# Build repo list for prompt
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

# ── Run Claude ───────────────────────────────────────────────────────

RUN_LOG="$LOGS_DIR/scan-${DATE_TAG}.log"
touch "$RUN_LOG" && chmod 600 "$RUN_LOG"

log "Spawning Claude to scan $REPO_COUNT public repos..."

timeout 2700 "$CLAUDE_BIN" \
  -p \
  --dangerously-skip-permissions \
  --verbose \
  --output-format stream-json \
  <<< "$PROMPT" \
  > "$RUN_LOG" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  log "TIMEOUT: Scan exceeded 45 minute timeout"
fi

# ── Extract result ───────────────────────────────────────────────────

RESULT=$(grep -m1 '"type":"result"' "$RUN_LOG" 2>/dev/null \
  | jq -r '.result // "No result extracted"' 2>/dev/null \
  | head -c 4000 \
  || echo "No result extracted")

COST=$(grep '"type":"result"' "$RUN_LOG" 2>/dev/null \
  | jq -r 'select(.total_cost_usd) | "$\(.total_cost_usd | tostring | .[0:6])"' 2>/dev/null \
  | tail -1 \
  || echo "unknown")
[ -z "$COST" ] && COST="unknown"

# ── Parse findings ──────────────────────────────────────────────────

CRITICAL_COUNT=$(echo "$RESULT" | grep -c 'SEVERITY: critical' || echo "0")
HIGH_COUNT=$(echo "$RESULT" | grep -c 'SEVERITY: high' || echo "0")
MEDIUM_COUNT=$(echo "$RESULT" | grep -c 'SEVERITY: medium' || echo "0")
LOW_COUNT=$(echo "$RESULT" | grep -c 'SEVERITY: low' || echo "0")
TOTAL_FINDINGS=$((CRITICAL_COUNT + HIGH_COUNT + MEDIUM_COUNT + LOW_COUNT))

# ── Update state (atomic write) ─────────────────────────────────────

STATE_TMP="$STATE_FILE.tmp"
jq -n \
  --argjson num "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit "$EXIT_CODE" \
  --arg cost "$COST" \
  --argjson critical "$CRITICAL_COUNT" \
  --argjson high "$HIGH_COUNT" \
  --argjson total "$TOTAL_FINDINGS" \
  '{run_number: $num, last_run: $ts, last_exit_code: $exit, last_cost: $cost, critical_findings: $critical, high_findings: $high, total_findings: $total}' \
  > "$STATE_TMP"
mv "$STATE_TMP" "$STATE_FILE"

# ── Log result ───────────────────────────────────────────────────────

if [ $EXIT_CODE -eq 0 ]; then
  log "DONE: Scan #$RUN_NUMBER — $TOTAL_FINDINGS findings ($CRITICAL_COUNT critical, $HIGH_COUNT high, $MEDIUM_COUNT medium, $LOW_COUNT low) — cost: $COST"
else
  log "FAIL: Scan #$RUN_NUMBER exited with code $EXIT_CODE (cost: $COST)"
fi

# ── Post to Discord #security-risks ─────────────────────────────────

post_to_discord() {
  local webhook="$1" msg="$2"
  [ -z "$webhook" ] && return 0
  msg="${msg:0:1990}"
  local payload
  payload=$(jq -n --arg content "$msg" '{"username": "Security Scanner", "content": $content}')
  curl -s -X POST "$webhook" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1 || true
}

if [ -z "$SECURITY_RISKS_WEBHOOK" ]; then
  log "WARN: SECURITY_RISKS_WEBHOOK not set — Discord notifications disabled"
fi

if [ $EXIT_CODE -eq 0 ]; then
  if [ "$TOTAL_FINDINGS" -gt 0 ]; then
    SEVERITY_EMOJI=""
    if [ "$CRITICAL_COUNT" -gt 0 ]; then
      SEVERITY_EMOJI="🚨"
    elif [ "$HIGH_COUNT" -gt 0 ]; then
      SEVERITY_EMOJI="⚠️"
    else
      SEVERITY_EMOJI="ℹ️"
    fi

    post_to_discord "$SECURITY_RISKS_WEBHOOK" "${SEVERITY_EMOJI} **Security Scan #$RUN_NUMBER** ($DATE_TAG) — **$TOTAL_FINDINGS finding(s)**

**Critical:** $CRITICAL_COUNT | **High:** $HIGH_COUNT | **Medium:** $MEDIUM_COUNT | **Low:** $LOW_COUNT
**Cost:** $COST | **Repos scanned:** $REPO_COUNT

${RESULT:0:1400}"
  else
    post_to_discord "$SECURITY_RISKS_WEBHOOK" "✅ **Security Scan #$RUN_NUMBER** ($DATE_TAG) — **All clear**

No sensitive data found across $REPO_COUNT public repos.
Cost: $COST"
  fi
else
  post_to_discord "$SECURITY_RISKS_WEBHOOK" "❌ **Security Scan #$RUN_NUMBER FAILED** ($DATE_TAG)

Exit code: $EXIT_CODE | Cost: $COST
Check logs at ~/repos/agentGuidance/scripts/security-scanner/logs/"
fi

# ── Email alert for critical/high findings ───────────────────────────

if [ "$GMAIL_ALERT_ENABLED" = "true" ] && { [ "$CRITICAL_COUNT" -gt 0 ] || [ "$HIGH_COUNT" -gt 0 ]; }; then
  CRITICAL_FINDINGS=$(echo "$RESULT" | sed -n '/SEVERITY: critical/,/^---/p' | head -60)
  HIGH_FINDINGS=$(echo "$RESULT" | sed -n '/SEVERITY: high/,/^---/p' | head -60)

  EMAIL_BODY="Security scan #$RUN_NUMBER ($DATE_TAG) found sensitive data in your public repositories.

## Critical Findings ($CRITICAL_COUNT)

$CRITICAL_FINDINGS

## High Findings ($HIGH_COUNT)

$HIGH_FINDINGS

---

**Repos scanned:** $REPO_COUNT
**Scan cost:** $COST

**Action required:** Review and remediate these findings. Critical findings may include exposed secrets that should be rotated immediately."

  EMAIL_FILE="$LOGS_DIR/email-alert-${DATE_TAG}.txt"
  echo "$EMAIL_BODY" > "$EMAIL_FILE"
  chmod 600 "$EMAIL_FILE"

  SUBJECT="[Security Alert] Scan #$RUN_NUMBER — $CRITICAL_COUNT critical, $HIGH_COUNT high findings"
  if node "$SCRIPT_DIR/send-email.js" "$SUBJECT" "$EMAIL_FILE" 2>&1; then
    log "EMAIL: Alert sent (critical: $CRITICAL_COUNT, high: $HIGH_COUNT)"
  else
    log "EMAIL: Failed to send alert — check SMTP config"
  fi
fi

# ── Clean up old logs (keep last 30) ────────────────────────────────

ls -t "$LOGS_DIR"/scan-*.log 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true

log "Security scan #$RUN_NUMBER complete."
