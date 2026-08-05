#!/usr/bin/env bash
# compact-memory-index.sh — keep MEMORY.md (the always-loaded memory index)
# under its context budget by NORMALISING ITS FORMAT, then capping hook length.
#
# Root cause this defends against (two of them):
#
#   1. FORMAT TAX. The harness instructs every session to append entries as
#      "- [name.md](name.md) — hook". That writes the filename TWICE and adds
#      markdown link syntax around it. Measured on the 166-entry primary index:
#      only 30% of the bytes were hook text (the actual signal); 26% was the
#      duplicated filename and ~31% was syntax. Normalising to "name: hook"
#      cut the index 51% (5,196 -> 2,565 tokens) with ZERO information loss.
#      Every name and every hook survives; only the syntax is dropped.
#
#   2. UNBOUNDED HOOKS. propagate-learning.sh appends the learning SUMMARY as
#      the index hook. Over hundreds of entries the index blows past budget and
#      only loads partially, silently dropping the tail.
#
# It also evicts DEMOTION RECORDS from the hot path: entries retired from the
# always-loaded index used to be parked in an HTML comment inside MEMORY.md,
# which still cost context (620 tokens) to describe entries deliberately
# removed to save context. Those now live in INDEX-LAZY.md, which is NOT
# loaded into context.
#
# This script is NON-DESTRUCTIVE: it rewrites entry FORMAT and truncates hook
# text, never the link target. It never deletes a memory file, and the name is
# always preserved, so context-on-demand (Read the topic file) still works.
#
# IDEMPOTENT: running it on an already-compact index is a no-op. That matters,
# because the harness keeps instructing sessions to append in link format, so
# this hook re-normalises the drift on every SessionStart, forever.
#
# Machine-agnostic: it compacts EVERY index it finds under
# ~/.claude/projects/*/memory/MEMORY.md, so it works on any host (WSL, VM, pc2)
# regardless of the project-path slug.
#
# Usage:
#   compact-memory-index.sh            # compact every index in place
#   compact-memory-index.sh --check    # report only, do not modify (exit 3 if any over budget)
#   HOOK_MAX=88 SOFT_LIMIT=22000 HARD_LIMIT=24400 compact-memory-index.sh
#
# Designed to run as a silent SessionStart hook: it self-heals every session
# and only prints to stdout (which the harness injects into context) when it
# actually had to compact or when an index is STILL over budget after
# compaction — meaning entries need pruning, a judgement call for the agent.

set -uo pipefail

HOOK_MAX="${HOOK_MAX:-88}"        # max chars of hook text per entry
SOFT_LIMIT="${SOFT_LIMIT:-22500}" # warn/act target in bytes
HARD_LIMIT="${HARD_LIMIT:-24400}" # the real context-load ceiling in bytes
CHECK_ONLY=false
[ "${1:-}" = "--check" ] && CHECK_ONLY=true

MEMORY_BASE="$HOME/.claude/projects"
[ -d "$MEMORY_BASE" ] || exit 0

RC=0

process_one() {
  local INDEX="$1"
  local before needs_work
  before=$(wc -c < "$INDEX" 2>/dev/null || echo 0)

  # Does this index need anything done to it? Three triggers:
  #   - any link-format entry still present (format drift from a new session)
  #   - any demotion HTML comment still in the hot path
  #   - over the soft byte limit
  needs_work=0
  grep -qE '^- \[[^]]+\]\(' "$INDEX" 2>/dev/null && needs_work=1
  grep -q '<!--' "$INDEX" 2>/dev/null && needs_work=1
  [ "$before" -gt "$SOFT_LIMIT" ] && needs_work=1
  [ "$needs_work" = 0 ] && return 0

  if $CHECK_ONLY; then
    # NB: grep -c prints "0" AND exits 1 on no-match, so a `|| echo 0` fallback
    # would concatenate a second zero onto the captured value. Swallow the exit
    # status instead and let grep's own "0" stand.
    local nlink ncomment
    nlink=$(grep -cE '^- \[[^]]+\]\(' "$INDEX" 2>/dev/null); nlink=${nlink:-0}
    ncomment=$(grep -c '<!--' "$INDEX" 2>/dev/null); ncomment=${ncomment:-0}
    echo "${INDEX}: ${before} bytes (soft ${SOFT_LIMIT}, hard ${HARD_LIMIT}); ${nlink} link-format entries, ${ncomment} demotion comments."
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
    HOOK_MAX="$HOOK_MAX" LAZY_FILE="$(dirname "$INDEX")/INDEX-LAZY.md" \
      python3 - "$INDEX" > "$TMP" <<'PY'
import os, re, sys

hook_max = int(os.environ["HOOK_MAX"])
lazy_file = os.environ["LAZY_FILE"]
path = sys.argv[1]

HEADER = ("# memory index — format: `name: hook` (each name is <name>.md in this "
          "directory). Append new entries in THIS format, not as markdown links.")

# Link format written by the harness / propagate-learning.sh:
#   "- [name.md](name.md) — hook"   (separator is space + em dash + space)
# Capture BOTH halves. They are usually identical, but a handful of entries
# were written with a prose title as the link text and the real filename only
# in the target (e.g. "[job-search-master-plan](project_job_search_master_plan.md)").
# The target is the file that actually exists, so it always wins — taking the
# text would silently orphan the memory file.
link_re = re.compile(r'^- \[([^\]]+)\]\(([^)]*)\)\s*[—-]\s*(.*)$')
# Already-compact format: "name: hook". Memory names never contain spaces or
# colons, which is what makes this unambiguous against hook text that does.
compact_re = re.compile(r'^([A-Za-z0-9][A-Za-z0-9_.\-]*):\s*(.*)$')

def clip(hook):
    hook = hook.strip()
    if len(hook) <= hook_max:
        return hook
    cut = hook[:hook_max]
    sp = cut.rfind(" ")
    if sp > hook_max * 0.6:        # prefer a word boundary when it's not too early
        cut = cut[:sp]
    return cut.rstrip(" ,;:.-—") + "…"   # ellipsis marks truncation

entries, demoted, passthrough = [], [], []
seen = set()

with open(path, encoding="utf-8") as fh:
    text = fh.read()

# Evict demotion records from the hot path. They name entries already removed
# from the index, so paying context for them is pure waste.
for m in re.finditer(r'<!--(.*?)-->', text, re.S):
    body = " ".join(m.group(1).split())
    demoted.append(body)
text = re.sub(r'<!--.*?-->\n?', '', text, flags=re.S)

for line in text.split("\n"):
    line = line.rstrip()
    if not line:
        continue
    if line.startswith("# memory index"):   # our own header; re-emitted below
        continue
    m = link_re.match(line)
    if m:
        text, target = m.group(1), m.group(2).strip()
        name = target or text          # target names the real file; text is cosmetic
        if name.endswith(".md"):
            name = name[:-3]
        entries.append((name, clip(m.group(3))))
        continue
    m = compact_re.match(line)
    if m and not line.startswith(("#", "-", "*", ">")):
        entries.append((m.group(1), clip(m.group(2))))
        continue
    passthrough.append(line)   # headers, prose, anything we don't recognise

# De-duplicate by name, keeping the FIRST occurrence (oldest wins; a concurrent
# double-append of the same memory collapses to one line).
out = []
for name, hook in entries:
    if name in seen:
        continue
    seen.add(name)
    out.append(f"{name}: {hook}" if hook else name)

print(HEADER)
for line in passthrough:
    print(line)
for line in out:
    print(line)

# Append (never overwrite) evicted demotion records to the cold file.
if demoted:
    try:
        with open(lazy_file, "a", encoding="utf-8") as fh:
            if fh.tell() == 0:
                fh.write("# Demoted memory entries — NOT loaded into context.\n"
                         "# Files remain on disk in this directory and stay recall-searchable.\n\n")
            for d in demoted:
                fh.write(d + "\n")
    except OSError:
        pass   # fail-open: never let the cold file block index compaction
PY

    if [ ! -s "$TMP" ]; then rm -f "$TMP"; exit 0; fi
    mv "$TMP" "$INDEX"
    after=$(wc -c < "$INDEX" 2>/dev/null || echo 0)

    if [ "$after" -lt "$before" ]; then
      echo "${INDEX} compacted: ${before} -> ${after} bytes (format normalised, hooks capped at ${HOOK_MAX} chars)."
    fi
    if [ "$after" -gt "$HARD_LIMIT" ]; then
      n=$(grep -cE '^[A-Za-z0-9][A-Za-z0-9_.-]*:' "$INDEX" 2>/dev/null || echo '?')
      echo "WARNING: ${INDEX} is still ${after} bytes (> ${HARD_LIMIT} hard limit) across ${n} entries after compaction. Prune or consolidate stale/superseded/duplicated memories to fit — format normalisation alone is not enough."
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
