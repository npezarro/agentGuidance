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
# Usage:
#   compact-memory-index.sh            # compact the primary index in place
#   compact-memory-index.sh --check    # report only, do not modify (exit 3 if over budget)
#   MAX_LINE=145 SOFT_LIMIT=22000 HARD_LIMIT=24400 compact-memory-index.sh
#
# Designed to run as a silent SessionStart hook: it self-heals every session
# and only prints to stdout (which the harness injects into context) when it
# actually had to compact or when the file is STILL over budget after
# compaction — meaning entries need pruning, a judgement call for the agent.

set -uo pipefail

MAX_LINE="${MAX_LINE:-128}"       # max chars per index line (link + hook)
SOFT_LIMIT="${SOFT_LIMIT:-22500}" # warn/act target in bytes
HARD_LIMIT="${HARD_LIMIT:-24400}" # the real context-load ceiling in bytes
CHECK_ONLY=false
[ "${1:-}" = "--check" ] && CHECK_ONLY=true

MEMORY_BASE="$HOME/.claude/projects"
INDEX=""
for d in "$MEMORY_BASE"/-mnt-c-Users-*/memory "$MEMORY_BASE"/-home-npezarro/memory; do
  if [ -f "$d/MEMORY.md" ]; then INDEX="$d/MEMORY.md"; break; fi
done
[ -z "$INDEX" ] && exit 0

before=$(wc -c < "$INDEX" 2>/dev/null || echo 0)

# If already comfortably under the soft limit and no over-long lines, do nothing.
longest=$(awk '{ if (length > m) m = length } END { print m+0 }' "$INDEX")
if [ "$before" -le "$SOFT_LIMIT" ] && [ "$longest" -le "$MAX_LINE" ]; then
  exit 0
fi

if $CHECK_ONLY; then
  echo "MEMORY.md index: ${before} bytes (soft ${SOFT_LIMIT}, hard ${HARD_LIMIT}), longest line ${longest} chars."
  [ "$before" -gt "$HARD_LIMIT" ] && exit 3
  exit 0
fi

# Serialize with concurrent appenders (learning-agent crons, other sessions)
# on the same lock file so a read-modify-write never clobbers a fresh append.
# propagate-learning.sh takes the same "$INDEX.lock" around its >> append.
exec 9>"$INDEX.lock" 2>/dev/null || true
flock -w 5 9 2>/dev/null || true
before=$(wc -c < "$INDEX" 2>/dev/null || echo 0)  # re-measure under the lock

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
  echo "MEMORY.md index compacted: ${before} -> ${after} bytes (cap ${MAX_LINE} chars/line)."
fi
if [ "$after" -gt "$HARD_LIMIT" ]; then
  n=$(grep -c '^- \[' "$INDEX" 2>/dev/null || echo '?')
  echo "WARNING: MEMORY.md index is still ${after} bytes (> ${HARD_LIMIT} hard limit) across ${n} entries after hook compaction. Prune or consolidate stale/superseded/duplicated memories to fit — hook truncation alone is not enough."
fi
exit 0
