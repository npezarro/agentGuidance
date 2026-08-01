#!/usr/bin/env bash
# claim-guard.sh <warn|deny> — cross-session write-collision guard.
#
# The problem it fixes (2026-07-17 and again 2026-07-30): several Claude sessions run
# in the same ~/repos checkout with --dangerously-skip-permissions, and nothing tells
# them about each other. One session's `git add -A` closeout committed another's work;
# on 2026-07-30 two live sessions committed browser-agent progress.md 58 seconds apart
# and only survived because both diffs happened to be insert-only.
#
# The existing defenses were the wrong shape: session-heartbeat.sh answers "is a human
# live" (so autonomousDev crons defer), and check-repo-writer.sh answers "is this repo
# owned by an agent". Neither answers "is another session writing THIS path right now".
#
# Two modes:
#   warn  (PostToolUse Edit|Write|Bash) — advisory. Names the other live session, the
#         path, and how stale your read may be. Deduped so each collision is reported
#         once per session.
#   deny  (PreToolUse Bash) — blocks only the blast-radius commands, the ones that take
#         another session's uncommitted work with them:
#           git add -A / --all / .
#           git commit -a / -am / --all
#           rsync --delete into /var/www/<app>
#         Everything else stays advisory. A denial is escapable and logged, never a
#         silent wall: append "<target>\t<reason>" to /tmp/claude-claim-ack-<sid>.
#
# Liveness comes from /tmp/claude-session-alive-<sid> (session-heartbeat.sh), so a stale
# ledger from a session that exited weeks ago can never block or warn.
set -uo pipefail

MODE="${1:-warn}"
INPUT=$(cat)

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0

LIB="$HOME/repos/agentGuidance/hooks/lib/write-target-inference.sh"
[ -f "$LIB" ] || exit 0
# shellcheck source=lib/write-target-inference.sh
. "$LIB"

LIVE_WINDOW="${CLAIM_GUARD_LIVE_WINDOW:-1800}"    # other session counts as live
TOUCH_WINDOW="${CLAIM_GUARD_TOUCH_WINDOW:-1800}"  # their write counts as recent
NOW=$(date +%s)
NOTED="/tmp/claude-claim-noted-${SID}"
ACK="/tmp/claude-claim-ack-${SID}"
LOG="$HOME/.claude/logs/claim-guard.log"

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
PAYLOAD_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

log_event() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$SID" "$1" "$2" >> "$LOG" 2>/dev/null
}

short() { printf '%s' "${1:0:8}"; }

mins_ago() { echo $(( ($NOW - $1 + 30) / 60 )); }

session_is_live() {
  local f="/tmp/claude-session-alive-$1" m
  [ -f "$f" ] || return 1
  m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  [ $(( NOW - m )) -le "$LIVE_WINDOW" ]
}

# A subagent runs under its own session id but is MY work, not a competing writer.
# Its transcript lives under <my session>/subagents/.
is_my_subagent() {
  local other="$1" hit
  hit=$(find "$HOME/.claude/projects" -maxdepth 4 -path "*/${SID}/subagents/*${other}*" -print -quit 2>/dev/null)
  [ -n "$hit" ]
}

# live_entries -> "<sid>\t<repo_root>\t<file>\t<epoch>" for other live sessions' recent writes
live_entries() {
  local f b sid m
  for f in /tmp/claude-repos-touched-* /tmp/claude-repos-claimed-*; do
    [ -f "$f" ] || continue
    m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    [ $(( NOW - m )) -le "$TOUCH_WINDOW" ] || continue
    b=$(basename "$f")
    sid="${b#claude-repos-touched-}"
    sid="${sid#claude-repos-claimed-}"
    [ "$sid" = "$SID" ] && continue
    session_is_live "$sid" || continue
    is_my_subagent "$sid" && continue
    awk -F'\t' -v sid="$sid" -v now="$NOW" -v win="$TOUCH_WINDOW" -v fb="$m" '
      NF >= 2 {
        ts = (NF >= 3 && $3 ~ /^[0-9]+$/) ? $3 : fb
        if (now - ts <= win) print sid "\t" $1 "\t" $2 "\t" ts
      }' "$f" 2>/dev/null
  done
}

noted() { [ -f "$NOTED" ] && grep -qxF "$1" "$NOTED" 2>/dev/null; }
note()  { printf '%s\n' "$1" >> "$NOTED" 2>/dev/null; }

# ---------------------------------------------------------------- warn mode
if [ "$MODE" = "warn" ]; then
  TARGETS=""
  case "$TOOL" in
    Edit|Write|NotebookEdit)
      TARGETS=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
      ;;
    Bash)
      [ -z "$CMD" ] && exit 0
      wti_is_write_cmd "$CMD" || exit 0
      eff=$(wti_effective_cwd "$CMD" "$PAYLOAD_CWD")
      [ -n "$eff" ] && [ -d "$eff" ] || exit 0
      TARGETS=$(wti_candidate_paths "$CMD" "$eff")
      ;;
    *) exit 0 ;;
  esac
  [ -z "$TARGETS" ] && exit 0

  ENTRIES=$(live_entries)
  [ -z "$ENTRIES" ] && exit 0

  OUT=""
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    repo=$(wti_repo_root "$target")
    [ -z "$repo" ] && continue

    # Same file, another live session. The dangerous case: your in-memory copy is stale,
    # and a full-file rewrite silently drops their lines.
    hit=$(printf '%s\n' "$ENTRIES" | awk -F'\t' -v t="$target" '$3 == t { print $1 "\t" $4 }' | sort -u | tail -1)
    if [ -n "$hit" ]; then
      osid=$(printf '%s' "$hit" | cut -f1)
      ots=$(printf '%s' "$hit" | cut -f2)
      key="file|${target}|${osid}"
      if ! noted "$key"; then
        note "$key"
        OUT="${OUT}CONCURRENT WRITER: $(basename "$target") was also written $(mins_ago "$ots")m ago by live session $(short "$osid") (same file, same checkout). Re-read it before your next write, never full-file rewrite it, and stage explicit paths when you commit. Full path: ${target}
"
        log_event "warn-file" "$target by $osid"
      fi
      continue
    fi

    # Same repo, different file. Cheaper signal, reported once per repo per other session.
    hit=$(printf '%s\n' "$ENTRIES" | awk -F'\t' -v r="$repo" '$2 == r { print $1 "\t" $4 "\t" $3 }' | sort -u | tail -1)
    if [ -n "$hit" ]; then
      osid=$(printf '%s' "$hit" | cut -f1)
      ots=$(printf '%s' "$hit" | cut -f2)
      ofile=$(printf '%s' "$hit" | cut -f3)
      key="repo|${repo}|${osid}"
      if ! noted "$key"; then
        note "$key"
        OUT="${OUT}CONCURRENT SESSION: $(basename "$repo") is also being written by live session $(short "$osid") ($(basename "$ofile"), $(mins_ago "$ots")m ago). Different files so far. Stage explicit paths when you commit; \`git add -A\` here would take their work too.
"
        log_event "warn-repo" "$repo by $osid"
      fi
    fi
  done <<< "$TARGETS"

  [ -n "$OUT" ] && printf '%s' "$OUT"
  exit 0
fi

# ---------------------------------------------------------------- deny mode
[ "$MODE" = "deny" ] || exit 0
[ "$TOOL" = "Bash" ] || exit 0
[ -z "$CMD" ] && exit 0

KIND=""
FIX=""
if printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^ ]+)?[[:space:]]+add([[:space:]]|$)' \
   && printf '%s' "$CMD" | grep -qE '[[:space:]](-A|--all|\.)([[:space:]]|$)'; then
  KIND="git add -A/--all/."
  FIX="Stage explicit paths instead: git add <the files you actually changed>."
elif printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^ ]+)?[[:space:]]+commit([[:space:]]|$)' \
     && printf '%s' "$CMD" | grep -qE '[[:space:]](-a|-am|-ma|--all)([[:space:]]|$)'; then
  KIND="git commit -a/--all"
  FIX="Stage explicit paths first, then commit without -a: git add <your files> && git commit -m '...'."
elif printf '%s' "$CMD" | grep -qE 'rsync[^;&|]*--delete' && printf '%s' "$CMD" | grep -qE '/var/www/'; then
  KIND="rsync --delete into /var/www"
  FIX="Coordinate the deploy target with the other session before mirroring, or deploy after it finishes."
fi
[ -z "$KIND" ] && exit 0

ack_allows() {
  [ -f "$ACK" ] || return 1
  awk -F'\t' -v t="$1" '$1 == t && $2 != "" { found=1; print $2; exit } END { exit !found }' "$ACK" 2>/dev/null
}

deny() {  # $1 = target label, $2 = detail line
  local reason
  if reason=$(ack_allows "$1"); then
    log_event "ack-override" "$1: $reason"
    exit 0
  fi
  log_event "deny" "$1: $KIND"
  cat >&2 <<EOF
CLAIM GUARD: blocked \`${KIND}\` — ${1} is also being written by another LIVE session right now.
${2}
${FIX}
This command would sweep their uncommitted work into your commit (or delete files they are still writing). It is the exact failure from 2026-07-17.
If you have verified it is safe (e.g. you confirmed the other session is idle and its tree is clean), record the decision and retry:
  printf '%s\t%s\n' '${1}' '<reason>' >> ${ACK}
EOF
  exit 2
}

if [ "$KIND" = "rsync --delete into /var/www" ]; then
  # rsync is SRC... DEST, so the contested path is the LAST /var/www argument.
  # Taking the first one reads `rsync /var/www/staging-shopper/ /var/www/shopper/`
  # as a claim on staging and lets the production overwrite through.
  DEST=$(printf '%s' "$CMD" | grep -oE '/var/www/[A-Za-z0-9_.-]+' | tail -1)
  [ -z "$DEST" ] && exit 0
  APP=$(basename "$DEST")
  REGISTRY="$HOME/repos/privateContext/deploy-registry.json"
  SVC="$APP"
  if [ -f "$REGISTRY" ]; then
    mapped=$(jq -r --arg a "$APP" \
      '.services | to_entries[] | select(.key == $a or .value.pm2 == $a or .value.repo == $a) | .key' \
      "$REGISTRY" 2>/dev/null | head -1)
    [ -n "$mapped" ] && SVC="$mapped"
  fi
  for f in /tmp/claude-deploys-*; do
    [ -f "$f" ] || continue
    m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    [ $(( NOW - m )) -le "$TOUCH_WINDOW" ] || continue
    osid=$(basename "$f"); osid="${osid#claude-deploys-}"
    [ "$osid" = "$SID" ] && continue
    session_is_live "$osid" || continue
    is_my_subagent "$osid" && continue
    if grep -qxF "$SVC" "$f" 2>/dev/null; then
      deny "$DEST" "Live session $(short "$osid") deployed '${SVC}' $(mins_ago "$m")m ago and may still be mid-deploy."
    fi
  done
  exit 0
fi

# git arms: resolve the repo this command would act on
EFF_CWD=$(wti_effective_cwd "$CMD" "$PAYLOAD_CWD")
GIT_C=$(printf '%s' "$CMD" | grep -oE 'git[[:space:]]+-C[[:space:]]+[^ &;|]+' | head -1 | sed -E 's/.*-C[[:space:]]+//' | tr -d "'\"")
if [ -n "$GIT_C" ]; then
  GIT_C=$(wti_expand "$GIT_C")
  case "$GIT_C" in
    /*) EFF_CWD="$GIT_C" ;;
    *)  EFF_CWD="${EFF_CWD}/${GIT_C}" ;;
  esac
fi

ENTRIES=$(live_entries)
[ -z "$ENTRIES" ] && exit 0

REPO=""
if [ -n "$EFF_CWD" ] && [ -d "$EFF_CWD" ]; then
  REPO=$(git -C "$EFF_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [ -z "$REPO" ]; then
  # The target dir did not resolve, usually an unexpanded variable (`cd $REPO && ...`).
  # Waving the command through would be a silent miss, so fall back to any contested
  # repo the command names outright, comparing against a HOME-normalized copy.
  # Residual gap, accepted: a target built entirely from a variable this hook cannot
  # resolve is not covered by the deny arm. The warn arm still fires on the writes.
  CMD_NORM=$(printf '%s' "$CMD" | sed -e "s#\${HOME}#${HOME}#g" -e "s#\$HOME#${HOME}#g" -e "s#~/#${HOME}/#g")
  while IFS= read -r cand_repo; do
    [ -z "$cand_repo" ] && continue
    if printf '%s' "$CMD_NORM" | grep -qF "$cand_repo"; then REPO="$cand_repo"; break; fi
  done <<< "$(printf '%s\n' "$ENTRIES" | cut -f2 | sort -u)"
fi
[ -z "$REPO" ] && exit 0
HIT=$(printf '%s\n' "$ENTRIES" | awk -F'\t' -v r="$REPO" '$2 == r { print $1 "\t" $4 "\t" $3 }' | sort -u | tail -1)
[ -z "$HIT" ] && exit 0

OSID=$(printf '%s' "$HIT" | cut -f1)
OTS=$(printf '%s' "$HIT" | cut -f2)
OFILE=$(printf '%s' "$HIT" | cut -f3)
deny "$(basename "$REPO")" "Live session $(short "$OSID") wrote $(basename "$OFILE") there $(mins_ago "$OTS")m ago."
