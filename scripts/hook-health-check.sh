#!/usr/bin/env bash
# hook-health-check.sh — Weekly health check for Stop hook dependencies.
#
# Verifies that the GitHub raw CDN (for hook scripts), Discord webhook,
# and WordPress API are all reachable. Emails on failure.
#
# Usage: bash scripts/hook-health-check.sh
# Cron:  0 7 * * 1  (Mondays at 7 AM PT)

set -uo pipefail

LOG_DIR="${HOME}/repos/agentGuidance/reports"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/hook-health-check.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TIMESTAMP] $*" | tee -a "$LOG_FILE"; }

FAILURES=()

# --- 1. GitHub raw CDN (hook scripts must be fetchable) ---
for script in post-to-discord.sh post-closeout.sh post-to-wordpress.sh; do
  URL="https://raw.githubusercontent.com/npezarro/agentGuidance/main/hooks/${script}"
  HTTP_CODE=$(curl -sf --max-time 10 -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" != "200" ]; then
    FAILURES+=("GitHub raw CDN: ${script} returned HTTP ${HTTP_CODE}")
    log "FAIL: $script (HTTP $HTTP_CODE)"
  else
    log "OK: $script"
  fi
done

# --- 2. agent.md (SessionStart hook dependency) ---
AGENT_CODE=$(curl -sf --max-time 10 -o /dev/null -w "%{http_code}" \
  "https://raw.githubusercontent.com/npezarro/agentGuidance/main/agent.md" 2>/dev/null || echo "000")
if [ "$AGENT_CODE" != "200" ]; then
  FAILURES+=("GitHub raw CDN: agent.md returned HTTP ${AGENT_CODE}")
  log "FAIL: agent.md (HTTP $AGENT_CODE)"
else
  log "OK: agent.md"
fi

# --- 3. Discord webhook (post-to-discord.sh dependency) ---
# Load webhook URL from env
source "$HOME/.env" 2>/dev/null || true
if [ -n "${DISCORD_WEBHOOK_URL:-}" ]; then
  # GET on a webhook URL returns webhook info without posting
  DISCORD_CODE=$(curl -sf --max-time 10 -o /dev/null -w "%{http_code}" "$DISCORD_WEBHOOK_URL" 2>/dev/null || echo "000")
  if [ "$DISCORD_CODE" != "200" ]; then
    FAILURES+=("Discord webhook returned HTTP ${DISCORD_CODE}")
    log "FAIL: Discord webhook (HTTP $DISCORD_CODE)"
  else
    log "OK: Discord webhook"
  fi
else
  FAILURES+=("Discord webhook: DISCORD_WEBHOOK_URL not set in ~/.env")
  log "FAIL: DISCORD_WEBHOOK_URL not configured"
fi

# --- 4. WordPress REST API (post-to-wordpress.sh dependency) ---
WP_SITE="${WP_SITE:-https://example.com}"
WP_CODE=$(curl -sf --max-time 10 -o /dev/null -w "%{http_code}" "${WP_SITE}/wp-json/wp/v2/posts?per_page=1" 2>/dev/null || echo "000")
if [ "$WP_CODE" = "200" ] || [ "$WP_CODE" = "401" ]; then
  # 401 is fine — means the API is reachable but needs auth (expected for private posts)
  log "OK: WordPress API (HTTP $WP_CODE)"
else
  FAILURES+=("WordPress API at ${WP_SITE} returned HTTP ${WP_CODE}")
  log "FAIL: WordPress API (HTTP $WP_CODE)"
fi

# --- Report ---
FAIL_COUNT=${#FAILURES[@]}
log "Health check complete: ${FAIL_COUNT} failure(s)"

if [ "$FAIL_COUNT" -eq 0 ]; then
  log "All checks passed"
  exit 0
fi

# --- Send alert email ---
# Source credentials
[ -f "$HOME/.env" ] && source "$HOME/.env"
[ -f "$HOME/.secrets" ] && source "$HOME/.secrets"
SMTP_USER="${SMTP_USER:-}"
ALERT_EMAIL="${ALERT_EMAIL:-}"
REPORT_PW=$(grep "^GMAIL_APP_PW=" "$HOME/.secrets" 2>/dev/null | sed "s/^GMAIL_APP_PW=//; s/^'//; s/'$//" || true)
if [ -z "$REPORT_PW" ]; then
  # Fallback to security scanner env
  REPORT_PW=$(grep "^SMTP_PASS=" "$HOME/repos/agentGuidance/scripts/security-scanner/.env" 2>/dev/null | sed 's/^SMTP_PASS=//; s/^"//; s/"$//' || true)
fi

if [ -n "$REPORT_PW" ]; then
  FAILURE_LIST=""
  for f in "${FAILURES[@]}"; do
    FAILURE_LIST="${FAILURE_LIST}<li>${f}</li>"
  done

  python3 << EMAILEOF
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

sender = "$SMTP_USER"
pw = "$REPORT_PW"
recipient = "$ALERT_EMAIL"

msg = MIMEMultipart("alternative")
msg["Subject"] = "Hook Health Check — ${FAIL_COUNT} failure(s) detected"
msg["From"] = "Hook Monitor <" + sender + ">"
msg["To"] = recipient

html = """<html><body style='font-family: sans-serif; max-width: 600px; margin: 0 auto;'>
<div style='background: #c62828; color: white; padding: 20px; text-align: center;'>
  <h2 style='margin: 0;'>Hook Health Check Failed</h2>
</div>
<div style='padding: 20px; background: #f9f9f9;'>
  <p><strong>${FAIL_COUNT}</strong> hook dependency check(s) failed at <strong>$TIMESTAMP</strong>:</p>
  <ul style='color: #c62828;'>$FAILURE_LIST</ul>
  <p style='margin-top: 16px; color: #666;'>If these dependencies are down, Stop hooks (Discord posting, WordPress posting)
  and SessionStart hooks (agent.md fetch) will silently fail until restored.</p>
  <div style='margin-top: 12px; padding: 10px; background: #fff3e0; border-left: 3px solid #e65100;'>
    <strong>Action:</strong> Check the failing endpoints manually. If GitHub raw CDN is down,
    hooks will fall back gracefully. If Discord/WP are down, turns won't be logged.
  </div>
</div>
<div style='padding: 12px 20px; background: #eee; color: #666; font-size: 12px; text-align: center;'>
  Hook Health Monitor — Weekly on Mondays at 7 AM PT
</div>
</body></html>"""

msg.attach(MIMEText(html, "html"))
try:
    with smtplib.SMTP("smtp.gmail.com", 587) as s:
        s.starttls()
        s.login(sender, pw)
        s.sendmail(sender, recipient, msg.as_string())
    print("Alert email sent")
except Exception as e:
    print(f"Email failed: {e}")
EMAILEOF
  log "Alert email sent"
else
  log "WARNING: No email credentials found, skipping alert"
fi
