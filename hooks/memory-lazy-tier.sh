#!/usr/bin/env bash
# memory-lazy-tier.sh — demote never-read reference memories out of the
# always-loaded index and retrieve them on demand by keyword.
#
# ============================================================================
# THIS IS SHIPPED BUT NOT ENABLED. Nothing changes until `enable` is run.
# ============================================================================
#
# It is gated on xp-001 (readout 2026-08-19), which is measuring whether the
# retrieval below is a good enough safety net to demote the entries at all.
# The decision rule: ship only if INTERACTIVE recall >= 80% AND candidate
# injections/interactive prompt <= 1.0. This file exists so a "go" verdict is a
# one-line flip instead of a fresh project.
#
#   ENABLE  (only after a go verdict):
#       ~/repos/agentGuidance/hooks/memory-lazy-tier.sh enable
#   KILL SWITCH (full reversal, restores the index and unregisters the hook):
#       ~/repos/agentGuidance/hooks/memory-lazy-tier.sh disable
#   KILL SWITCH (instant, no file edits — export in the environment):
#       MEMORY_LAZY_TIER=off
#
# ----------------------------------------------------------------------------
# WHAT IT DOES
#
# `demote` moves the candidate entries out of MEMORY.md (which is injected into
# every session prefix) and into the LAZY-TIER block of INDEX-LAZY.md (which is
# not). The memory FILES are never touched: they stay on disk, stay
# recall-searchable, and stay readable by name. Only their index lines move.
#
# `retrieve` is a UserPromptSubmit hook. It scores the prompt against the FULL
# index (hot entries + lazy entries), takes the top-K, and injects the hooks of
# whichever of those live in the lazy tier. Hot entries are already in context,
# so they are scored but never injected — they are there to compete. A hot
# entry beating a lazy one is the signal that the lazy one was not the answer.
#
# MATCHER: copied verbatim from experiments/memory-lazy-shadow.sh (rig
# 54893c36fdbd). Copied, not imported, because that directory is FROZEN until
# the readout and importing would couple the shipped path to a file that must
# not change. hooks/memory-lazy-tier.selftest.sh replays the shadow log through
# this copy and asserts identical top-K output, so the copy cannot silently
# drift from the version the experiment actually measured.
#
# ----------------------------------------------------------------------------
# THE FAILURE MODE, AND THE FALLBACK FOR IT
#
# A retrieval miss is SILENT. Nothing errors; a memory that would have informed
# the session simply is not there, and the session never learns it existed.
# That is strictly worse than a loud failure, so the mechanism does not rely on
# the matcher being right. Three layers, cheapest first:
#
#   1. POINTER LINE (always on, ~40 tokens, flat cost). One line at the top of
#      MEMORY.md states that a demoted tier exists, how many entries are in it,
#      and the exact grep to search it. This is what converts "silently absent"
#      into "one grep away": an agent that suspects a topic is missing can find
#      it without knowing this mechanism exists. It is the load-bearing layer.
#
#   2. NEAR-MISS NAMES (on by default, ~6.6 tokens/prompt measured, and only
#      on prompts where the tier injected NOTHING). Lazy entries that scored
#      competitively and were then suppressed get listed by NAME ONLY, no hook
#      text, capped at 2. This is the layer that surfaces without being asked,
#      which is the one thing the pointer line cannot do. Its scope was set by
#      replaying the shadow log, not by taste — see the comment at the `near =`
#      assignment for the numbers. Disable with MEMORY_LAZY_NEARMISS=0.
#
#   3. INDEX-LAZY.md IS A PLAIN-TEXT MANIFEST, not a database. Every demoted
#      entry keeps its `name: hook` line verbatim, so `grep -i` over it works
#      with no tooling and no knowledge of this script.
#
# What none of these fix: an agent that never suspects anything is missing gets
# no prompt to look. That is the honest residual risk of demotion, and it is
# exactly what xp-001's recall half is measuring. Do not read the fallback as
# making a low recall number safe to ship over.
#
# ----------------------------------------------------------------------------
# Fail-open throughout: any error exits 0 and prints nothing. This hook runs on
# every prompt; it must never be able to break a session.

set -uo pipefail

CMD="${1:-retrieve}"
[ $# -gt 0 ] && shift

# ---- paths ------------------------------------------------------------------
# Same index-resolution rule as compact-memory-index.sh: the current project's
# index, falling back to the human-interactive primary. Kept identical on
# purpose — the two hooks must always be operating on the same file.
resolve_memory_dir() {
  local base="$HOME/.claude/projects" proj slug d
  if [ -n "${MEMORY_LAZY_DIR:-}" ]; then printf '%s' "$MEMORY_LAZY_DIR"; return; fi
  proj="${CLAUDE_PROJECT_DIR:-${CLAUDE_WORKING_DIR:-$PWD}}"
  slug="$(printf '%s' "$proj" | sed 's#/#-#g')"
  if [ -f "$base/$slug/memory/MEMORY.md" ]; then printf '%s' "$base/$slug/memory"; return; fi
  shopt -s nullglob
  for d in "$base"/-mnt-c-Users-*/memory "$base"/-home-npezarro/memory; do
    if [ -f "$d/MEMORY.md" ]; then shopt -u nullglob; printf '%s' "$d"; return; fi
  done
  shopt -u nullglob
  printf '%s' ""
}

MEM_DIR="$(resolve_memory_dir)"
[ -n "$MEM_DIR" ] || exit 0
INDEX="$MEM_DIR/MEMORY.md"
LAZY="$MEM_DIR/INDEX-LAZY.md"

BEGIN_MARK="<!-- LAZY-TIER-BEGIN — retrieved on demand by hooks/memory-lazy-tier.sh; DO NOT hand-edit inside this block -->"
END_MARK="<!-- LAZY-TIER-END -->"

TOP_K="${MEMORY_LAZY_TOP_K:-2}"
MIN_SCORE="${MEMORY_LAZY_MIN_SCORE:-2}"
NEARMISS="${MEMORY_LAZY_NEARMISS:-1}"
NEARMISS_MAX="${MEMORY_LAZY_NEARMISS_MAX:-2}"
SETTINGS="${MEMORY_LAZY_SETTINGS:-$HOME/.claude/settings.json}"
HOOK_MARKER="hooks/memory-lazy-tier.sh"
HOOK_CMD='bash -c '"'"'printf "%s" "$(cat)" | $HOME/repos/agentGuidance/hooks/memory-lazy-tier.sh retrieve; exit 0'"'"''

# Runtime kill switch. Accepts the obvious spellings so nobody has to remember
# which one this script chose.
killed() {
  case "${MEMORY_LAZY_TIER:-}" in
    off|OFF|0|no|false|disabled) return 0 ;;
    *) return 1 ;;
  esac
}

# ---- shared: the lazy-tier block --------------------------------------------
# Emits the `name: hook` lines currently demoted. Empty output = tier inactive,
# which is the state this ships in.
lazy_block() {
  [ -f "$LAZY" ] || return 0
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    index($0, "LAZY-TIER-BEGIN") { on=1; next }
    index($0, "LAZY-TIER-END")   { on=0; next }
    on && $0 !~ /^[[:space:]]*$/ && $0 !~ /^#/ { print }
  ' "$LAZY"
}

case "$CMD" in

# =============================================================================
retrieve)
# =============================================================================
  input="$(cat)" || exit 0
  [ -n "$input" ] || exit 0
  [ -f "$INDEX" ] || exit 0

  block="$(lazy_block)"
  # Tier inactive: nothing has been demoted, so there is nothing to retrieve
  # and nothing to restore. Silent no-op. This is what makes registering the
  # hook harmless before the readout.
  [ -n "$block" ] || exit 0

  if killed; then
    # KILL SWITCH PATH. Do not match, do not filter — put the whole demoted
    # block back into context, which is behaviourally equivalent to never
    # having demoted it. Once per session: context injections persist across
    # turns, so repeating it every prompt would burn tokens for no gain.
    sid="$(printf '%s' "$input" | python3 -c 'import json,sys
try: print((json.load(sys.stdin).get("session_id") or "nosession"))
except Exception: print("nosession")' 2>/dev/null)"
    stamp="${TMPDIR:-/tmp}/memory-lazy-tier-restored-${sid//[^A-Za-z0-9_-]/_}"
    [ -e "$stamp" ] && exit 0
    : > "$stamp" 2>/dev/null || true
    echo "MEMORY INDEX (demoted tier, restored in full by MEMORY_LAZY_TIER=off):"
    printf '%s\n' "$block"
    exit 0
  fi

  # Scoring set = hot index + lazy tier, i.e. the full index as it stood before
  # demotion. Overridable so the selftest can replay the experiment's frozen
  # sets through this exact code path.
  HOOK_INPUT="$input" \
  MLT_INDEX_FILE="${MEMORY_LAZY_INDEX:-$INDEX}" \
  MLT_LAZY_INLINE="$block" \
  MLT_LAZY_FILE="${MEMORY_LAZY_CANDIDATES:-}" \
  TOP_K="$TOP_K" MIN_SCORE="$MIN_SCORE" \
  NEARMISS="$NEARMISS" NEARMISS_MAX="$NEARMISS_MAX" \
  DEBUG_JSON="${MEMORY_LAZY_DEBUG_JSON:-0}" MEM_DIR="$MEM_DIR" \
  python3 - <<'PY' 2>/dev/null || exit 0
import json, os, re, sys

top_k = int(os.environ["TOP_K"])
min_score = float(os.environ["MIN_SCORE"])
nearmiss_on = os.environ.get("NEARMISS", "1") not in ("0", "off", "no", "false")
nearmiss_max = int(os.environ.get("NEARMISS_MAX", "3"))
debug_json = os.environ.get("DEBUG_JSON", "0") == "1"

raw = os.environ.get("HOOK_INPUT", "")
try:
    payload = json.loads(raw)
except Exception:
    payload = {}
prompt = payload.get("prompt") or payload.get("user_prompt") or ""
if not prompt:
    sys.exit(0)

# --- index parsing -----------------------------------------------------------
# Same `name: hook` grammar compact-memory-index.sh normalises to. Memory names
# never contain spaces or colons, which is what makes this unambiguous against
# hook text that does.
ENTRY_RE = re.compile(r'^([A-Za-z0-9][A-Za-z0-9_.\-]*):\s*(.*)$')


def parse_lines(lines):
    out = []
    for line in lines:
        line = line.rstrip("\n")
        if not line or line.startswith(("#", "-", "*", ">")):
            continue
        m = ENTRY_RE.match(line)
        if m:
            out.append((m.group(1), m.group(2)))
    return out


def read_lines(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.readlines()
    except OSError:
        return []


hot = parse_lines(read_lines(os.environ["MLT_INDEX_FILE"]))

lazy_src = os.environ.get("MLT_LAZY_FILE") or ""
if lazy_src:                                   # selftest / replay override
    lazy = parse_lines(read_lines(lazy_src))
else:
    lazy = parse_lines(os.environ.get("MLT_LAZY_INLINE", "").split("\n"))

lazy_names = {n for n, _ in lazy}
lazy_hooks = dict(lazy)

# Union, hot first, deduped by name. If an entry somehow exists in both (a new
# session re-appending a demoted name to MEMORY.md), the hot copy wins and it
# is simply never injected — a duplicate in context is the harmless direction.
seen, entries = set(), []
for name, hook in hot + lazy:
    if name in seen:
        continue
    seen.add(name)
    entries.append((name, hook))

# ============================================================================
# MATCHER — copied verbatim from experiments/memory-lazy-shadow.sh, rig
# 54893c36fdbd. Do not "improve" it here: the selftest asserts byte-identical
# top-K against 200+ logged decisions, and any edit that changes a score
# changes what xp-001 measured. If the matcher needs to change, that is a new
# experiment, not a patch.
# ============================================================================
STOP = {
    "the","and","for","with","that","this","have","has","was","were","from","into",
    "what","when","where","which","would","could","should","about","there","their",
    "then","than","them","they","you","your","our","not","but","are","its","it's",
    "just","like","make","made","get","got","can","will","need","want","use","using",
    "run","ran","add","added","fix","fixed","new","old","see","also","still","only",
    "memory","md","claude",
}

TYPE_PREFIXES = ("project", "reference", "pattern", "feedback", "learning",
                 "rule", "infra", "rollup", "user", "custom")


def toks(s):
    return {t for t in re.split(r"[^a-z0-9]+", s.lower()) if len(t) > 3 and t not in STOP}


def strip_prefix(name):
    """Drop the memory-type prefix before tokenising.

    Without this, `project` is a name token on 39 of the 45 candidates, so any
    prompt containing the word 'project' scored +2 on nearly the whole set at
    once. That one defect produced 15 of the first 24 shadow injections. The
    prefix is a filing convention, never a topic.
    """
    for p in TYPE_PREFIXES:
        if name.startswith(p + "_"):
            return name[len(p) + 1:]
    return name


cands = []
for name, hook in entries:
    bare = strip_prefix(name)
    cands.append((name, toks(bare.replace("_", " ").replace("-", " ")), toks(hook), bare))

df = {}
for _, nt, ht, _ in cands:
    for t in nt | ht:
        df[t] = df.get(t, 0) + 1

noise_ceiling = max(2, len(cands) // 4)   # in >25% of candidates = filing vocabulary


def weight(t, base):
    d = df.get(t, 1)
    return 0.0 if d > noise_ceiling else base / (d ** 0.5)


pt = toks(prompt)
p_collapsed = re.sub(r"[^a-z0-9]", "", prompt.lower())

scored = []
for name, name_t, hook_t, bare in cands:
    score = (sum(weight(t, 2.0) for t in name_t & pt)
             + sum(weight(t, 1.0) for t in hook_t & pt))
    stem = re.sub(r"[^a-z0-9]", "", bare)
    if len(stem) > 5 and stem in p_collapsed:
        score += 3.0                      # whole-name substring: high precision
    if score >= min_score:
        scored.append((round(score, 2), name))

scored.sort(reverse=True)
above_floor = list(scored)                # kept for the near-miss fallback
if scored:
    top = scored[0][0]
    scored = [x for x in scored if x[0] >= 0.4 * top]
hits = [{"name": n, "score": s, "cand": n in lazy_names} for s, n in scored[:top_k]]
# ============================ END COPIED MATCHER =============================

inject = [h for h in hits if h["cand"]]
chosen = {h["name"] for h in hits}

# NEAR-MISS: lazy entries the matcher scored as competitive and then dropped.
# Two restrictions, both chosen from measurement on the 147 recoverable shadow
# decisions rather than from taste:
#
#   * SURVIVED THE MARGIN CUT, not merely cleared MIN_SCORE. Strictly the
#     tighter set (109 names vs 129 at cap 3), though the gap is small: when
#     the top score is low the 40% cut barely binds, so this does less work
#     than it looks like it should.
#   * ONLY WHEN NOTHING WAS INJECTED. This is what actually controls the cost,
#     and it targets the right population. Candidate injections fire on 26 of
#     147 prompts; on the other 121 the tier is invisible, which is where a
#     silent miss can happen at all. 47 of those 121 have a scoring lazy entry
#     — topically adjacent, suppressed, and otherwise never mentioned. Firing
#     only there costs ~6.6 tokens per prompt (measured, cap 2) against the
#     ~524 the tier saves per session; firing on every prompt costs ~9.5 and
#     spends most of it on prompts that already got a lazy hook.
#
# If the tier DID inject, the session already holds a live pointer into the
# demoted set plus the always-on pointer line, so naming runners-up is the
# lowest-value token in the budget.
near = []
if not inject:
    near = [n for s, n in scored if n not in chosen and n in lazy_names][:nearmiss_max]
near_loose = [n for s, n in above_floor if n not in chosen and n in lazy_names][:nearmiss_max]

if debug_json:
    print(json.dumps({"top": hits, "inject": [h["name"] for h in inject],
                      "near": near, "near_loose": near_loose}))
    sys.exit(0)

if not inject and not (nearmiss_on and near):
    sys.exit(0)

mem_dir = os.environ.get("MEM_DIR", "")
if inject:
    print(f"MEMORY (on-demand tier — matched this prompt; full note: cat {mem_dir}/<name>.md):")
    for h in inject:
        print(f"{h['name']}: {lazy_hooks.get(h['name'], '')}")
if nearmiss_on and near:
    print("  also demoted, scored lower, read if relevant: " + ", ".join(near))
PY
  exit 0
  ;;

# =============================================================================
demote)
# =============================================================================
  # Move candidate entries out of the hot index. Idempotent: entries already in
  # the lazy block are skipped, missing ones are reported, nothing is deleted.
  FROM="${1:-$HOME/.claude/memory-lazy-candidates.txt}"
  [ -f "$INDEX" ] || { echo "no index at $INDEX" >&2; exit 1; }
  [ -f "$FROM" ] || { echo "no candidate list at $FROM" >&2; exit 1; }

  # Same lock file compact-memory-index.sh and propagate-learning.sh take, so a
  # read-modify-write here cannot clobber a concurrent append.
  (
    if command -v flock >/dev/null 2>&1; then
      exec 9>"$INDEX.lock" 2>/dev/null || true
      flock -w 5 9 2>/dev/null || true
    fi
    INDEX="$INDEX" LAZY="$LAZY" FROM="$FROM" \
    BEGIN_MARK="$BEGIN_MARK" END_MARK="$END_MARK" \
    python3 - <<'PY'
import os, re, sys, datetime

index_p, lazy_p, from_p = os.environ["INDEX"], os.environ["LAZY"], os.environ["FROM"]
BEGIN, END = os.environ["BEGIN_MARK"], os.environ["END_MARK"]
ENTRY_RE = re.compile(r'^([A-Za-z0-9][A-Za-z0-9_.\-]*):\s*(.*)$')

want = set()
for line in open(from_p, encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#"):
        want.add(line.split(":")[0].strip())

lines = open(index_p, encoding="utf-8").read().split("\n")
keep, moved = [], []
for line in lines:
    m = ENTRY_RE.match(line)
    if m and not line.startswith(("#", "-", "*", ">")) and m.group(1) in want:
        moved.append(line.rstrip())
        continue
    keep.append(line)

# Read whatever is already demoted so this is idempotent and additive.
existing_block, before, after, state = [], [], [], "before"
if os.path.exists(lazy_p):
    for line in open(lazy_p, encoding="utf-8").read().split("\n"):
        if "LAZY-TIER-BEGIN" in line:
            state = "in"; continue
        if "LAZY-TIER-END" in line:
            state = "after"; continue
        (before if state == "before" else after if state == "after" else existing_block).append(line)

have = {ENTRY_RE.match(l).group(1) for l in existing_block if ENTRY_RE.match(l)}
new = [l for l in moved if ENTRY_RE.match(l).group(1) not in have]
block = [l for l in existing_block if l.strip()] + new

if not block:
    print("nothing to demote", file=sys.stderr)
    sys.exit(1)

if not before or not any(b.strip() for b in before):
    before = ["# Demoted memory entries — NOT loaded into context.",
              "# Files remain on disk in this directory and stay recall-searchable.", ""]

stamp = datetime.date.today().isoformat()
out = [l.rstrip() for l in before if l.strip() or l == ""]
out += [BEGIN,
        f"# {len(block)} entries, last demoted {stamp}. Retrieved on demand by",
        "# hooks/memory-lazy-tier.sh (UserPromptSubmit). grep -i here to search them all.",
        ""] + block + [END, ""]
out += [l.rstrip() for l in after]
open(lazy_p, "w", encoding="utf-8").write("\n".join(out).rstrip("\n") + "\n")

# The pointer line. `> ` prefix on purpose: compact-memory-index.sh routes any
# line starting with # - * > to passthrough, so it survives every compaction
# intact and lands at the top of the index. Without the prefix it would parse
# as an entry named "NOTE" and get its text clipped at 88 chars.
ptr_re = re.compile(r'^> \d+ more memories are demoted')
keep = [l for l in keep if not ptr_re.match(l)]
pointer = (f"> {len(block)} more memories are demoted to INDEX-LAZY.md in this directory and are "
           f"auto-surfaced by keyword. They are NOT listed above. If a topic seems missing, "
           f"search them: grep -i '<topic>' {lazy_p}")
hdr = 0
for i, l in enumerate(keep):
    if l.startswith("# memory index"):
        hdr = i + 1
        break
keep.insert(hdr, pointer)

open(index_p, "w", encoding="utf-8").write("\n".join(keep).rstrip("\n") + "\n")
print(f"demoted {len(new)} entries ({len(block)} in tier); "
      f"{len(want) - len([l for l in moved])} of {len(want)} listed names were not in the index")
PY
  )
  exit $?
  ;;

# =============================================================================
restore)
# =============================================================================
  # KILL SWITCH (permanent). Puts every demoted entry back into MEMORY.md and
  # empties the lazy block. The index returns to exactly its pre-demotion
  # content; only line order may differ, and compact-memory-index.sh does not
  # care about order.
  [ -f "$INDEX" ] || { echo "no index at $INDEX" >&2; exit 1; }
  (
    if command -v flock >/dev/null 2>&1; then
      exec 9>"$INDEX.lock" 2>/dev/null || true
      flock -w 5 9 2>/dev/null || true
    fi
    INDEX="$INDEX" LAZY="$LAZY" BEGIN_MARK="$BEGIN_MARK" END_MARK="$END_MARK" \
    python3 - <<'PY'
import os, re, sys

index_p, lazy_p = os.environ["INDEX"], os.environ["LAZY"]
BEGIN, END = os.environ["BEGIN_MARK"], os.environ["END_MARK"]
ENTRY_RE = re.compile(r'^([A-Za-z0-9][A-Za-z0-9_.\-]*):\s*(.*)$')

if not os.path.exists(lazy_p):
    print("nothing demoted"); sys.exit(0)

before, block, after, state = [], [], [], "before"
for line in open(lazy_p, encoding="utf-8").read().split("\n"):
    if "LAZY-TIER-BEGIN" in line:
        state = "in"; continue
    if "LAZY-TIER-END" in line:
        state = "after"; continue
    (before if state == "before" else after if state == "after" else block).append(line)

entries = [l.rstrip() for l in block if ENTRY_RE.match(l) and not l.startswith("#")]
if not entries:
    print("nothing demoted"); sys.exit(0)

lines = open(index_p, encoding="utf-8").read().split("\n")
have = {ENTRY_RE.match(l).group(1) for l in lines
        if ENTRY_RE.match(l) and not l.startswith(("#", "-", "*", ">"))}
back = [l for l in entries if ENTRY_RE.match(l).group(1) not in have]

# Drop the pointer line: with nothing demoted it would be a lie.
lines = [l for l in lines if not re.match(r'^> \d+ more memories are demoted', l)]
lines = [l for l in lines if l.strip() != ""] + back
open(index_p, "w", encoding="utf-8").write("\n".join(lines).rstrip("\n") + "\n")

open(lazy_p, "w", encoding="utf-8").write(
    "\n".join([l.rstrip() for l in before] + [l.rstrip() for l in after]).rstrip("\n") + "\n")
print(f"restored {len(back)} entries to the index ({len(entries) - len(back)} were already present)")
PY
  )
  exit $?
  ;;

# =============================================================================
enable|disable)
# =============================================================================
  # enable  = register the UserPromptSubmit hook + demote.
  # disable = restore + unregister. Either order is safe (an unregistered hook
  # with a populated tier just means no retrieval; a registered hook with an
  # empty tier is a silent no-op), but do the reversible half first.
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [ "$CMD" = "enable" ]; then
    "$self" demote "$@" || exit 1
  else
    "$self" restore || exit 1
  fi

  SETTINGS="$SETTINGS" ACTION="$CMD" HOOK_CMD="$HOOK_CMD" MARKER="$HOOK_MARKER" \
  python3 - <<'PY'
import json, os, shutil, sys

p = os.environ["SETTINGS"]
action, cmd, marker = os.environ["ACTION"], os.environ["HOOK_CMD"], os.environ["MARKER"]
if not os.path.exists(p):
    print(f"no settings at {p}", file=sys.stderr); sys.exit(1)
data = json.load(open(p, encoding="utf-8"))
hooks = data.setdefault("hooks", {}).setdefault("UserPromptSubmit", [])

present = any(marker in h.get("command", "")
              for grp in hooks for h in grp.get("hooks", []))

if action == "enable":
    if present:
        print("hook already registered"); sys.exit(0)
    hooks.append({"hooks": [{"type": "command", "command": cmd, "timeout": 5000}]})
else:
    if not present:
        print("hook was not registered"); sys.exit(0)
    for grp in hooks:
        grp["hooks"] = [h for h in grp.get("hooks", []) if marker not in h.get("command", "")]
    data["hooks"]["UserPromptSubmit"] = [g for g in hooks if g.get("hooks")]

shutil.copyfile(p, p + ".bak")
with open(p, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
print(f"hook {'registered' if action == 'enable' else 'unregistered'} in {p} (backup: {p}.bak)")
PY
  exit $?
  ;;

# =============================================================================
status)
# =============================================================================
  n_lazy=$(lazy_block | grep -c . 2>/dev/null); n_lazy=${n_lazy:-0}
  n_hot=$(grep -cE '^[A-Za-z0-9][A-Za-z0-9_.-]*:' "$INDEX" 2>/dev/null); n_hot=${n_hot:-0}
  reg="no"
  grep -q "$HOOK_MARKER" "$SETTINGS" 2>/dev/null && reg="yes"
  echo "index:        $INDEX ($(wc -c < "$INDEX" 2>/dev/null) bytes, $n_hot hot entries)"
  echo "lazy tier:    $LAZY ($n_lazy demoted entries)"
  echo "hook:         registered=$reg"
  echo "kill switch:  MEMORY_LAZY_TIER=${MEMORY_LAZY_TIER:-<unset>} ($(killed && echo ACTIVE || echo inactive))"
  if [ "$n_lazy" = 0 ] && [ "$reg" = "no" ]; then
    echo "state:        OFF (shipped, not enabled)"
  elif [ "$n_lazy" != 0 ] && [ "$reg" = "yes" ]; then
    echo "state:        ON"
  else
    echo "state:        PARTIAL — tier and hook disagree; run enable or disable to converge"
  fi
  ;;

*)
  echo "usage: memory-lazy-tier.sh {retrieve|demote|restore|enable|disable|status}" >&2
  exit 2
  ;;
esac
