#!/usr/bin/env bash
# reap-session-ledgers.sh [--dry-run] [--age SECONDS]
#
# Prune /tmp state left behind by Claude sessions that have exited.
#
# Sessions do not clean up after themselves, so these accumulate indefinitely:
#   /tmp/claude-session-alive-<sid>     liveness marker (session-heartbeat.sh)
#   /tmp/claude-repos-touched-<sid>     Edit/Write authorship ledger
#   /tmp/claude-repos-claimed-<sid>     Bash-inferred write ledger
#   /tmp/claude-claim-ack-<sid>         guard overrides
#   /tmp/claude-claim-noted-<sid>       warn-dedup state
#
# Two reasons this matters, neither of which is tidiness:
#
#   1. The raw marker count LIES about concurrency. Measured 2026-08-03: 59 alive
#      markers, ~2 sessions actually live. A human (or an agent) reading `ls` concludes
#      the ecosystem is far busier than it is; that misreading was made in this very
#      repo's history. The guards themselves are correct -- they compare mtime against
#      a 30-minute LIVE_WINDOW -- so this fixes the signal, not the guards.
#   2. claim-guard's live_entries() iterates EVERY touched+claimed ledger on every
#      qualifying Bash command. 211 files on the same date. That is per-command cost
#      paid forever for sessions that ended weeks ago.
#
# Safety: the reap age is 24h by default, 48x the 30-minute LIVE_WINDOW and 12x the
# 2-hour TOUCH_WINDOW, so nothing a guard could still consult is ever removed. A hard
# floor refuses any age below 2h regardless of flags -- there is no plausible reason to
# reap inside the window a live guard reads, and a too-eager reap would silently blind
# the guards rather than fail loudly.
set -uo pipefail

AGE=86400            # 24h
DRY=0
FLOOR=7200           # never reap younger than 2h, whatever is asked

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --age) AGE="${2:?--age needs seconds}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ "$AGE" -lt "$FLOOR" ]; then
  echo "refusing --age $AGE: floor is ${FLOOR}s, below it a live guard could still be reading these" >&2
  exit 2
fi

NOW=$(date +%s)
reaped=0; kept=0; bytes=0

# Collect every session id that has ANY state file, then judge the session as a whole.
# Keyed on the newest mtime across its files: a session whose marker is stale but whose
# ledger was written recently is still doing something, and half-reaping it would leave
# the guards with a ledger they cannot attribute.
sids=$(ls /tmp/claude-session-alive-* /tmp/claude-repos-touched-* /tmp/claude-repos-claimed-* \
          /tmp/claude-claim-ack-* /tmp/claude-claim-noted-* 2>/dev/null \
       | sed -E 's#^/tmp/claude-(session-alive|repos-touched|repos-claimed|claim-ack|claim-noted)-##' \
       | sort -u)

for sid in $sids; do
  [ -z "$sid" ] && continue
  files=""
  newest=0
  for f in "/tmp/claude-session-alive-$sid" "/tmp/claude-repos-touched-$sid" \
           "/tmp/claude-repos-claimed-$sid" "/tmp/claude-claim-ack-$sid" \
           "/tmp/claude-claim-noted-$sid"; do
    [ -e "$f" ] || continue
    files="$files $f"
    m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    [ "$m" -gt "$newest" ] && newest=$m
  done
  [ -z "$files" ] && continue

  if [ $(( NOW - newest )) -le "$AGE" ]; then
    kept=$((kept + 1))
    continue
  fi

  for f in $files; do
    b=$(stat -c %s "$f" 2>/dev/null || echo 0)
    bytes=$((bytes + b))
    [ "$DRY" = 1 ] || rm -f "$f"
  done
  reaped=$((reaped + 1))
done

printf '%s reaped=%s kept=%s freed=%sKB age=%ss%s\n' \
  "$(date -Iseconds)" "$reaped" "$kept" "$((bytes / 1024))" "$AGE" \
  "$([ "$DRY" = 1 ] && echo ' (DRY RUN)')"
