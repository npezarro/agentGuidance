#!/usr/bin/env bash
# with-resource-lock.sh <resource> [--timeout N] -- <command...>
#
# Serialize an operation on a SINGLETON resource across concurrent Claude sessions.
#
# Why this exists (2026-08-01): claim-guard.sh detects cross-session collisions and warns,
# or denies a short list of blast-radius git/rsync commands. Detection is the right shape
# for a shared *working tree*, where the real fix is isolation (per-session git worktrees:
# see guidance/concurrent-sessions.md). It is the WRONG shape for resources there is
# exactly one of — /var/www/<app>, a PM2 process, the live browser extension, the VM,
# ~/.claude/skills. You cannot isolate those; two sessions must take turns.
#
# An advisory warning you can proceed past does not serialize anything. This does.
#
#   with-resource-lock.sh browser-extension -- browser-cli ext-reload
#   with-resource-lock.sh deploy:shopper --timeout 600 -- bash deploy.sh
#
# Semantics:
#   - flock(2) on /tmp/claude-resource-lock-<resource>. The kernel releases it when the
#     holding process exits, INCLUDING on crash or kill, so a dead session can never
#     wedge a resource. That is the reason for flock over a hand-rolled lockfile.
#   - Waits up to --timeout (default 300s), then fails non-zero naming the holder.
#   - The command's exit code is passed through unchanged.
#   - Re-entrant within one process tree via CLAUDE_HELD_LOCKS, so a locked script that
#     calls another locked script does not deadlock against itself.
set -uo pipefail

LOCK_DIR="${CLAUDE_LOCK_DIR:-/tmp}"
TIMEOUT=300

usage() {
  cat >&2 <<'EOF'
Usage: with-resource-lock.sh <resource> [--timeout SECONDS] -- <command...>
       with-resource-lock.sh --list

  <resource>  Stable name for the contended singleton. Use a scheme:
                deploy:<app>        /var/www/<app> or a PM2 service
                browser-extension   the live Chrome extension (reload/CDP)
                vm:skills           ~/.claude/skills on the VM
  --list      Show currently held locks and who holds them.
EOF
  exit 2
}

# ---------------------------------------------------------------- --list
if [ "${1:-}" = "--list" ]; then
  found=0
  for meta in "$LOCK_DIR"/claude-resource-lock-*.holder; do
    [ -e "$meta" ] || continue
    lock="${meta%.holder}"
    # A lock with no live holder leaves its .holder file behind; flock -n succeeding
    # proves it is free, which is why the metadata file is never the source of truth.
    if flock -n "$lock" true 2>/dev/null; then
      status="FREE (stale metadata)"
    else
      status="HELD"
      found=1
    fi
    printf '%-8s %-28s %s\n' "$status" "$(basename "$lock" | sed 's/^claude-resource-lock-//')" "$(cat "$meta" 2>/dev/null)"
  done
  [ "$found" = 0 ] && echo "No resources currently held."
  exit 0
fi

RESOURCE="${1:-}"; shift || usage
[ -n "$RESOURCE" ] || usage

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --) shift; break ;;
    *) usage ;;
  esac
done
[ $# -gt 0 ] || usage

# Sanitize: the resource name becomes a filename, and ':' is meaningful to us but fine here.
SAFE=$(printf '%s' "$RESOURCE" | tr -c 'A-Za-z0-9:._-' '_')
LOCKFILE="$LOCK_DIR/claude-resource-lock-$SAFE"
META="$LOCKFILE.holder"

# Re-entrancy: a locked script invoking another locked script with the SAME resource
# would otherwise block on itself forever.
case ":${CLAUDE_HELD_LOCKS:-}:" in
  *":$SAFE:"*)
    exec "$@"
    ;;
esac

touch "$LOCKFILE" 2>/dev/null || { echo "with-resource-lock: cannot create $LOCKFILE" >&2; exec "$@"; }
exec 9>"$LOCKFILE"

if ! flock -w "$TIMEOUT" 9; then
  echo "RESOURCE LOCK TIMEOUT after ${TIMEOUT}s: '$RESOURCE' is held by another session." >&2
  [ -s "$META" ] && echo "  Holder: $(cat "$META")" >&2
  echo "  This resource is a singleton; two sessions cannot use it at once." >&2
  echo "  Wait, raise --timeout, or check 'with-resource-lock.sh --list'." >&2
  exit 75   # EX_TEMPFAIL: retryable, distinct from the command's own failures
fi

SID="${CLAUDE_SESSION_ID:-unknown}"
printf 'session=%s pid=%s since=%s cmd=%s\n' \
  "${SID:0:8}" "$$" "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" > "$META" 2>/dev/null || true

export CLAUDE_HELD_LOCKS="${CLAUDE_HELD_LOCKS:-}:$SAFE"

# `9>&-` closes the lock fd in the CHILD. Without it the child inherits fd 9, so the
# kernel keeps the lock until every descendant exits — and a command that daemonizes
# (pm2 restart, any nohup/setsid background service) would hand the inherited fd to a
# process that outlives the deploy and wedge the resource permanently. Verified
# 2026-08-01: before this, `sleep 30` spawned under the lock showed up holding the
# lockfile in /proc/<pid>/fd. Only this script's own fd 9 should pin the lock.
"$@" 9>&-
rc=$?

# Best-effort: blank the metadata so --list does not imply a holder that has gone.
# flock itself is released by the kernel when fd 9 closes at exit.
: > "$META" 2>/dev/null || true
exit $rc
