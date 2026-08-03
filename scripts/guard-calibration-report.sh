#!/usr/bin/env bash
# guard-calibration-report.sh [--days N] [--quiet]
#
# Reports the deny:ack ratio for the cross-session guards, and alerts when a guard looks
# MISCALIBRATED rather than when it is merely busy.
#
# Why this exists: worktree-guard shipped 2026-08-02 matching on repo instead of file, and
# inside ~15 minutes produced two denials against a peer with zero overlapping files. That
# peer acked both and carried on. Nothing alerted. The miscalibration was found only
# because someone happened to read the log.
#
# The signal is the ACK RATE, not the deny count. A guard that fires often and is obeyed
# is working. A guard that fires and gets overridden is being routed around, and an
# overridden guard is indistinguishable from an absent one -- worse, it trains the reflex
# that disables it everywhere else.
#
# Deliberately reports the raw numerators and denominators, never a bare verdict:
# ESSENTIAL rule 8 says prove the alarm before making it louder, and that is impossible
# from a summary that has thrown the counts away.
set -uo pipefail

DAYS=2
QUIET=0
ALERT_RATE=50        # percent of denials overridden that counts as miscalibration
ALERT_MIN=3          # ...but never alert on a handful of events; too small to mean anything

while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="${2:?--days needs a number}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

LOG="$HOME/.claude/logs/claim-guard.log"
[ -f "$LOG" ] || { echo "no guard log at $LOG"; exit 0; }

SINCE=$(date -d "$DAYS days ago" -Iseconds 2>/dev/null) || SINCE=""
[ -z "$SINCE" ] && { echo "date -d unavailable" >&2; exit 1; }

# Log format: <iso8601>\t<session_id>\t<event>\t<detail>
# ISO-8601 with a fixed offset sorts lexically, so a string compare is a correct window
# filter here and avoids parsing every line into an epoch.
#
# Counted by DISTINCT SESSION, not by log line. Two reasons raw lines mislead: one ack
# DECISION logs a line on every subsequent write to that repo, so a single override
# inflates without bound; and denials repeat while a session retries. The question is
# "how many sessions routed the guard around", which is a session-level fact.
#
# Synthetic ids from the test suite are excluded: session ids are UUIDs, fixtures are not,
# and leaving them in let a threshold get tuned against my own test runs.
read -r deny ack unresolved <<EOF
$(awk -F'\t' -v since="$SINCE" '
  $1 >= since && $2 ~ /^[0-9a-f]{8}-/ {
    if ($3 ~ /deny$/)                 seen_d[$2] = 1
    else if ($3 ~ /ack$/)             seen_a[$2] = 1
    else if ($3 == "unresolved-target") u++
  }
  END {
    for (k in seen_d) d++
    for (k in seen_a) a++
    printf "%d %d %d", d, a, u
  }
' "$LOG")
EOF

if [ "$deny" -eq 0 ]; then
  MSG="guard calibration (${DAYS}d): no real-session denials. Nothing to judge."
  [ "$QUIET" = 1 ] || echo "$MSG"
  exit 0
fi

# Sessions that overrode, over sessions that were denied. >100% is possible if a session
# acked without ever being denied; that is worth seeing, not worth hiding.
rate=$(( ack * 100 / deny ))
total="$deny"

# Per-guard breakdown, because "which guard is miscalibrated" is the actionable part.
BREAKDOWN=$(awk -F'\t' -v since="$SINCE" '
  $1 >= since && $2 ~ /^[0-9a-f]{8}-/ && ($3 ~ /deny$/ || $3 ~ /ack$/) {
    guard = ($3 ~ /^worktree/) ? "worktree-guard" : "claim-guard"
    if ($3 ~ /deny$/) sd[guard "\t" $2] = 1; else sa[guard "\t" $2] = 1
  }
  END {
    for (k in sd) { split(k, p, "\t"); d[p[1]]++ }
    for (k in sa) { split(k, p, "\t"); a[p[1]]++ }
    for (g in d) {
      printf "  %-15s sessions denied=%d, of which overrode=%d (%d%%)\n", \
        g, d[g], a[g]+0, (d[g] ? (a[g]+0)*100/d[g] : 0)
    }
  }
' "$LOG")

SUMMARY="guard calibration (${DAYS}d): ${deny} session(s) denied, ${ack} overrode, ${rate}% override rate"
[ "$unresolved" -gt 0 ] && SUMMARY="${SUMMARY}; ${unresolved} unresolved targets (guard blind spots)"

[ "$QUIET" = 1 ] || { echo "$SUMMARY"; echo "$BREAKDOWN"; }

# Alert only when it is actionable AND the sample is big enough to mean something.
if [ "$total" -ge "$ALERT_MIN" ] && [ "$rate" -ge "$ALERT_RATE" ]; then
  BODY="**${rate}% of denied sessions overrode the guard** in the last ${DAYS}d (${ack}/${total}).

${BREAKDOWN}

A high override rate means the guard is firing on things that are not hazards, not that sessions are misbehaving. An overridden guard is indistinguishable from an absent one, and it trains the reflex that disables the others. Narrow the condition or remove it.

Overrides: \`grep ack ~/.claude/logs/claim-guard.log\` · design: \`agentGuidance/guidance/concurrent-sessions.md\`"
  if [ -x "$HOME/repos/privateContext/discord-webhook.sh" ]; then
    "$HOME/repos/privateContext/discord-webhook.sh" "Guard miscalibration: ${rate}% of denials overridden" "$BODY" >/dev/null 2>&1 \
      && echo "  alerted Discord" || echo "  Discord alert FAILED" >&2
  else
    echo "  (no discord-webhook.sh; alert not sent)" >&2
  fi
fi
