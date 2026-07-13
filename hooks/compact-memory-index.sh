#!/usr/bin/env bash
# compact-memory-index.sh — keep MEMORY.md (the always-loaded memory index)
# under its context budget by capping every index entry to a one-line hook.
#
# Root cause this defends against: propagate-learning.sh appends the full,
# unbounded learning SUMMARY as the index hook. Over hundreds of entries the
# index blows past the ~24.4KB budget and only loads partially, silently
# dropping the tail of the index.
#
# This script is NON-DESTRUCTIVE: it only truncates the hook text after the
# "— " separator on each entry line. It never deletes a memory file and never
# touches the link, so context-on-demand (Read the topic file) still works.
#
# Machine-agnostic: it compacts EVERY index it finds under
# ~/.claude/projects/*/memory/MEMORY.md, so it works on any host (WSL, VM, pc2)
# regardless of the project-path slug.
#
# Usage:
#   compact-memory-index.sh            # compact every index in place
#   compact-memory-index.sh --check    # report only, do not modify (exit 3 if any over budget)
#   MAX_LINE=145 SOFT_LIMIT=22000 HARD_LIMIT=24400 compact-memory-index.sh
#
# Designed to run as a silent SessionStart hook: it self-heals every session
# and only prints to stdout (which the harness injects into context) when it
# actually had to compact or when an index is STILL over budget after
# compaction — meaning entries need pruning, a judgement call for the agent.

set -uo pipefail

MAX_LINE="${MAX_LINE:-128}"       # max chars per index line (link + hook)
SOFT_LIMIT="${SOFT_LIMIT:-22500}" # warn/act target in bytes
HARD_LIMIT="${HARD_LIMIT:-24400}" # the real context-load ceiling in bytes
CHECK_ONLY=false
[ "${1:-}" = "--check" ] && CHECK_ONLY=true

MEMORY_BASE="$HOME/.claude/projects"
[ -d "$MEMORY_BASE" ] || exit 0

RC=0

process_one() {
  local INDEX="$1"
  local before longest
  before=$(wc -c < "$INDEX" 2>/dev/null || echo 0)

  # Already comfortably under the soft limit and no over-long lines: skip.
  longest=$(awk '{ if (length > m) m = length } END { print m+0 }' "$INDEX")
  if [ "$before" -le "$SOFT_LIMIT" ] && [ "$longest" -le "$MAX_LINE" ]; then
    return 0
  fi

  if $CHECK_ONLY; then
    echo "${INDEX}: ${before} bytes (soft ${SOFT_LIMIT}, hard ${HARD_LIMIT}), longest line ${longest} chars."
    [ "$before" -gt "$HARD_LIMIT" ] && RC=3
    return 0
  fi

  # Serialize with concurrent appenders (learning-agent crons, other sessions)
  # on the same lock file so a read-modify-write never clobbers a fresh append.
  # propagate-learning.sh takes the same "$INDEX.lock" around its >> append.
  # flock is not universal (absent on some Macs/minimal boxes): fall back to an
  # mkdir lock with the same wait-up-to-5s-then-proceed semantics.
  (
    if command -v flock >/dev/null 2>&1; then
      exec 9>"$INDEX.lock" 2>/dev/null || true
      flock -w 5 9 2>/dev/null || true
    else
      LOCK_D="$INDEX.lock.d" LOCK_HELD=false WAITED=0
      while :; do
        if mkdir "$LOCK_D" 2>/dev/null; then LOCK_HELD=true; break; fi
        [ "$WAITED" -ge 5 ] && break   # timed out: proceed anyway (matches flock -w 5 || true)
        sleep 1; WAITED=$((WAITED + 1))
      done
      # Release on every exit path of this subshell (including the empty-TMP exit 0)
      trap '[ "${LOCK_HELD:-false}" = true ] && rmdir "${LOCK_D}" 2>/dev/null || true' EXIT
    fi
    before=$(wc -c < "$INDEX" 2>/dev/null || echo 0)  # re-measure under the lock

    local TMP after n
    TMP="$(mktemp)"
    MAX_LINE="$MAX_LINE" python3 - "$INDEX" > "$TMP" <<'PY'
import os, re, sys

max_line = int(os.environ["MAX_LINE"])
path = sys.argv[1]
# entry: "- [name](link) — hook"  (separator is space + em dash + space)
sep = " — "
entry_re = re.compile(r'^(- \[[^\]]+\]\([^)]+\))' + re.escape(sep) + r'(.*)$')

with open(path, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        m = entry_re.match(line)
        if not m:
            print(line)
            continue
        prefix, hook = m.group(1), m.group(2)
        full = prefix + sep + hook
        if len(full) <= max_line:
            print(full)
            continue
        budget = max_line - len(prefix) - len(sep)
        if budget < 20:            # link alone is huge; keep a minimal hook
            budget = 20
        hook = hook.strip()
        if len(hook) > budget:
            cut = hook[:budget]
            sp = cut.rfind(" ")
            if sp > budget * 0.6:  # prefer a word boundary when it's not too early
                cut = cut[:sp]
            hook = cut.rstrip(" ,;:.-—") + "…"  # ellipsis marks truncation
        print(prefix + sep + hook)
PY

    if [ ! -s "$TMP" ]; then rm -f "$TMP"; exit 0; fi
    mv "$TMP" "$INDEX"
    after=$(wc -c < "$INDEX" 2>/dev/null || echo 0)

    if [ "$after" -lt "$before" ]; then
      echo "${INDEX} compacted: ${before} -> ${after} bytes (cap ${MAX_LINE} chars/line)."
    fi
    if [ "$after" -gt "$HARD_LIMIT" ]; then
      n=$(grep -c '^- \[' "$INDEX" 2>/dev/null || echo '?')
      echo "WARNING: ${INDEX} is still ${after} bytes (> ${HARD_LIMIT} hard limit) across ${n} entries after hook compaction. Prune or consolidate stale/superseded/duplicated memories to fit — hook truncation alone is not enough."
    fi
  )
}

shopt -s nullglob

if $CHECK_ONLY; then
  # Audit mode: report on every index found on the machine.
  found=0
  for INDEX in "$MEMORY_BASE"/*/memory/MEMORY.md; do
    [ -f "$INDEX" ] || continue
    found=1
    process_one "$INDEX"
  done
  shopt -u nullglob
  [ "$found" = 0 ] && exit 0
  exit $RC
fi

# Hook mode: heal only the CURRENT session's project index. Each project
# self-heals during its own sessions, so this stays silent about unrelated
# projects (e.g. a runaway autonomous-agent index) instead of spamming every
# session's context with another project's prune warning.
PROJ_DIR="${CLAUDE_PROJECT_DIR:-${CLAUDE_WORKING_DIR:-$PWD}}"
SLUG="$(printf '%s' "$PROJ_DIR" | sed 's#/#-#g')"
PRIMARY="$MEMORY_BASE/$SLUG/memory/MEMORY.md"

if [ ! -f "$PRIMARY" ]; then
  # Fall back to the human-interactive primary index (not the largest, so we
  # never latch onto a runaway autonomous index by accident).
  PRIMARY=""
  for d in "$MEMORY_BASE"/-mnt-c-Users-*/memory "$MEMORY_BASE"/-home-npezarro/memory; do
    if [ -f "$d/MEMORY.md" ]; then PRIMARY="$d/MEMORY.md"; break; fi
  done
fi
shopt -u nullglob
[ -z "$PRIMARY" ] || [ ! -f "$PRIMARY" ] && exit 0

process_one "$PRIMARY"
exit $RC
