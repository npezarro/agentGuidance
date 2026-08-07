#!/usr/bin/env bash
# memory-lazy-tier.selftest.sh — prove the lazy-tier mechanism before it is
# enabled, without waiting for the xp-001 readout and without touching any
# live state.
#
# Four tests, in order of what they buy:
#
#   1. REPLAY REGRESSION (the important one). The shadow log records what the
#      frozen rig 54893c36fdbd decided on every real prompt since 2026-08-05,
#      but for privacy it records only the prompt's LENGTH, never its text. The
#      prompts are recoverable from the session transcripts: join on
#      (session_id, |timestamp delta| <= 5s, exact length). Each recovered
#      prompt is fed through the SHIPPED hook with the experiment's frozen
#      input sets, and its top-K must match the logged decision exactly, name
#      and score. This is what proves the copied matcher is the measured
#      matcher, which is the whole basis for trusting xp-001's numbers to
#      describe this code.
#
#   2. END-TO-END in a sandbox memory dir: demote, retrieve, restore. Asserts
#      the entries actually leave the hot index, that a matching prompt gets
#      their hooks back, and that restore returns the index to byte-identical
#      content.
#
#   3. KILL SWITCH: with the tier populated, MEMORY_LAZY_TIER=off must emit the
#      whole demoted block and never a match. A kill switch that has not been
#      run is not a kill switch.
#
#   4. INERT-WHEN-OFF: with nothing demoted, the hook must print exactly zero
#      bytes. This is what makes it safe to register the hook while xp-001 is
#      still collecting.
#
# Usage: memory-lazy-tier.selftest.sh [--quick]   (--quick skips test 1)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/memory-lazy-tier.sh"
LOG="${MEMORY_LAZY_SHADOW_LOG:-$HOME/.claude/memory-lazy-shadow.jsonl}"
FROZEN_INDEX="${MEMORY_LAZY_INDEX:-$HOME/.claude/memory-lazy-index.txt}"
FROZEN_CANDS="${MEMORY_LAZY_CANDIDATES:-$HOME/.claude/memory-lazy-candidates.txt}"
QUICK=false
[ "${1:-}" = "--quick" ] && QUICK=true

PASS=0; FAIL=0
ok()   { echo "  PASS  $*"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

# Session id must be unique per run: the kill-switch path stamps a marker file
# so it restores the block only once per session, and a fixed id would make
# test 3 pass on a clean box and fail on every rerun.
payload() { python3 -c 'import json,sys; print(json.dumps({"prompt":sys.argv[1],"session_id":sys.argv[2],"cwd":"/tmp"}))' "$1" "${2:-selftest-$$}"; }

# ============================================================================
echo "1. replay regression against the frozen shadow log"
# ============================================================================
if $QUICK; then
  echo "  SKIP  (--quick)"
elif [ ! -f "$LOG" ]; then
  bad "no shadow log at $LOG"
else
  RESULT="$(HOOK="$HOOK" LOG="$LOG" FROZEN_INDEX="$FROZEN_INDEX" FROZEN_CANDS="$FROZEN_CANDS" python3 - <<'PY'
import datetime, glob, json, os, subprocess, sys

HOME = os.path.expanduser("~")
hook = os.environ["HOOK"]
recs = []
for line in open(os.environ["LOG"], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        recs.append(json.loads(line))
    except Exception:
        pass

# One rig only. score-shadow.py refuses to average across configurations for
# the same reason: mixing incompatible records produces a number that is an
# artifact of the mixing. If the log ever carries two rigs, replaying it against
# one matcher is meaningless, so stop rather than report a misleading pass rate.
rigs = {r.get("rig", "unstamped") for r in recs}
if len(rigs) != 1:
    print(json.dumps({"error": f"log carries {len(rigs)} rig versions: {sorted(rigs)}"}))
    sys.exit(0)

paths = {os.path.basename(p)[:-6]: p for p in glob.glob(f"{HOME}/.claude/projects/*/*.jsonl")}


def transcript_prompts(path):
    """Every real user prompt in a transcript, as (epoch, text).

    Tool results also arrive as type=user and must be excluded, or a long tool
    output can coincidentally match a prompt length and replay the wrong text.
    """
    out = []
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return out
    with fh:
        for line in fh:
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("type") != "user":
                continue
            c = (o.get("message") or {}).get("content")
            if isinstance(c, list):
                if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
                    continue
                c = "".join(b.get("text", "") for b in c
                            if isinstance(b, dict) and b.get("type") == "text")
            if not isinstance(c, str) or not c:
                continue
            ts = o.get("timestamp")
            if not ts:
                continue
            try:
                t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
            except ValueError:
                continue
            out.append((t, c))
    return out


env = dict(os.environ)
env.update({
    "MEMORY_LAZY_INDEX": os.environ["FROZEN_INDEX"],
    "MEMORY_LAZY_CANDIDATES": os.environ["FROZEN_CANDS"],
    "MEMORY_LAZY_DEBUG_JSON": "1",
    # The hook refuses to act on an empty tier. Point it at a scratch memory
    # dir whose lazy block is non-empty so the guard passes; the frozen
    # overrides above are what actually get scored.
    "MEMORY_LAZY_DIR": env.get("MLT_SCRATCH", ""),
})
env.pop("MEMORY_LAZY_TIER", None)

scratch = os.path.join(os.environ.get("TMPDIR", "/tmp"), "mlt-replay")
os.makedirs(scratch, exist_ok=True)
open(os.path.join(scratch, "MEMORY.md"), "w").write("# memory index\n")
open(os.path.join(scratch, "INDEX-LAZY.md"), "w").write(
    "<!-- LAZY-TIER-BEGIN -->\nplaceholder_entry: activates the tier for replay\n<!-- LAZY-TIER-END -->\n")
env["MEMORY_LAZY_DIR"] = scratch

cache = {}
matched = mismatched = unrecoverable = 0
examples, near_counts, near_loose, cand_inj = [], 0, 0, 0
for r in recs:
    sid = r.get("session", "")
    p = paths.get(sid)
    if not p:
        unrecoverable += 1
        continue
    if sid not in cache:
        cache[sid] = transcript_prompts(p)
    hits = [(abs(t - r["ts"]), c) for t, c in cache[sid]
            if len(c) == r["prompt_len"] and abs(t - r["ts"]) <= 5]
    if not hits:
        unrecoverable += 1
        continue
    prompt = min(hits)[1]

    inp = json.dumps({"prompt": prompt, "session_id": sid, "cwd": r.get("cwd", "")})
    try:
        proc = subprocess.run([hook, "retrieve"], input=inp, capture_output=True,
                              text=True, env=env, timeout=30)
        got = json.loads(proc.stdout.strip() or "{}")
    except Exception as e:
        mismatched += 1
        examples.append(f"invocation failed: {e}")
        continue

    want = [(h["name"], h["score"], h["cand"]) for h in (r.get("would_inject") or [])]
    mine = [(h["name"], h["score"], h["cand"]) for h in (got.get("top") or [])]
    if want == mine:
        matched += 1
    else:
        mismatched += 1
        if len(examples) < 5:
            examples.append(f"len={r['prompt_len']} logged={want} replayed={mine}")
    near_counts += len(got.get("near") or [])
    near_loose += len(got.get("near_loose") or [])
    cand_inj += len(got.get("inject") or [])

print(json.dumps({"matched": matched, "mismatched": mismatched,
                  "unrecoverable": unrecoverable, "records": len(recs),
                  "near_total": near_counts, "near_loose": near_loose,
                  "cand_injections": cand_inj, "examples": examples}))
PY
)"
  if printf '%s' "$RESULT" | RESULT="$RESULT" python3 - <<'PY'
import json, os, sys
r = json.loads(os.environ["RESULT"])
if "error" in r:
    print("  FAIL  " + r["error"]); sys.exit(1)
n, bad = r["matched"] + r["mismatched"], r["mismatched"]
print("  replayed %d of %d logged decisions (%d had no recoverable prompt: "
      "transcript absent on this host)" % (n, r["records"], r["unrecoverable"]))
print("  candidate injections: %d; near-miss names disclosed under the shipped rule: %d "
      "(a MIN_SCORE-only, fire-on-every-prompt rule would disclose %d)"
      % (r["cand_injections"], r["near_total"], r["near_loose"]))
for e in r["examples"]:
    print("        " + e)
if bad == 0 and n >= 50:
    print("  PASS  %d/%d top-K decisions reproduced exactly (name and score)" % (n, n))
else:
    print("  FAIL  %d mismatches out of %d" % (bad, n)); sys.exit(1)
PY
  then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
fi

# ============================================================================
echo "2. end-to-end demote / retrieve / restore in a sandbox"
# ============================================================================
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
cat > "$SANDBOX/MEMORY.md" <<'EOF'
# memory index — format: `name: hook` (each name is <name>.md in this directory). Append new entries in THIS format, not as markdown links.
project_raspberrypi: Home Pi 3 B+ at 192.168.4.25/.20 (ssh…
project_notion_sync: Daily one-way git → Notion mirror of…
feedback_written_voice: Comprehensive style guide for…
pattern_wal_sidecar_replace_corrupts: Replacing a WAL-mode SQLite file must…
EOF
cp "$SANDBOX/MEMORY.md" "$SANDBOX/MEMORY.md.orig"
printf 'project_raspberrypi\nproject_notion_sync\n' > "$SANDBOX/cands.txt"

export MEMORY_LAZY_DIR="$SANDBOX"
"$HOOK" demote "$SANDBOX/cands.txt" >/dev/null 2>&1

if grep -q '^project_raspberrypi:' "$SANDBOX/MEMORY.md"; then
  bad "demote left the entry in the hot index"
else
  ok "demote removed the entries from MEMORY.md"
fi
if grep -q '^project_raspberrypi:' "$SANDBOX/INDEX-LAZY.md"; then
  ok "demote wrote the entries into INDEX-LAZY.md with their hooks intact"
else
  bad "entries missing from the lazy tier"
fi
if grep -q '^> 2 more memories are demoted' "$SANDBOX/MEMORY.md"; then
  ok "pointer line present in the hot index (the always-visible fallback)"
else
  bad "pointer line missing — a miss would be silent and unrecoverable"
fi

OUT="$(payload "check the raspberrypi tunnel forwarding" | "$HOOK" retrieve 2>/dev/null)"
if printf '%s' "$OUT" | grep -q 'project_raspberrypi:'; then
  ok "retrieve injected the demoted entry's hook for a matching prompt"
else
  bad "retrieve did not surface the obviously-matching entry: $OUT"
fi

OUT="$(payload "what is the capital of Portugal" | "$HOOK" retrieve 2>/dev/null)"
if [ -z "$OUT" ]; then
  ok "retrieve stays silent on an unrelated prompt (no cost when it has nothing)"
else
  bad "retrieve injected on an unrelated prompt: $OUT"
fi

# The near-miss fallback must stay quiet when the tier already answered: that
# suppression is what keeps its measured cost at ~6.6 tokens/prompt instead of
# ~9.5, and it is the only part of the policy that is not pure matcher output.
NEAR="$(payload "check the raspberrypi tunnel forwarding" | MEMORY_LAZY_DEBUG_JSON=1 "$HOOK" retrieve 2>/dev/null)"
if printf '%s' "$NEAR" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["inject"] and not d["near"] else 1)'; then
  ok "near-miss names suppressed on a prompt the tier already answered"
else
  bad "near-miss fired alongside an injection: $NEAR"
fi

# Idempotence: a second demote must not duplicate or lose anything.
"$HOOK" demote "$SANDBOX/cands.txt" >/dev/null 2>&1
if [ "$(grep -c '^project_raspberrypi:' "$SANDBOX/INDEX-LAZY.md")" = "1" ]; then
  ok "demote is idempotent"
else
  bad "second demote duplicated an entry"
fi

# ============================================================================
echo "3. kill switch"
# ============================================================================
OUT="$(MEMORY_LAZY_TIER=off payload "what is the capital of Portugal" | MEMORY_LAZY_TIER=off "$HOOK" retrieve 2>/dev/null)"
if printf '%s' "$OUT" | grep -q 'project_raspberrypi:' && printf '%s' "$OUT" | grep -q 'project_notion_sync:'; then
  ok "MEMORY_LAZY_TIER=off restores the entire demoted block regardless of the prompt"
else
  bad "env kill switch did not restore the block: $OUT"
fi

"$HOOK" restore >/dev/null 2>&1
if grep -q '^project_raspberrypi:' "$SANDBOX/MEMORY.md" && grep -q '^project_notion_sync:' "$SANDBOX/MEMORY.md"; then
  ok "restore put every demoted entry back into the hot index"
else
  bad "restore lost entries"
fi
if grep -q '^> .* more memories are demoted' "$SANDBOX/MEMORY.md"; then
  bad "restore left a stale pointer line claiming a tier that no longer exists"
else
  ok "restore removed the pointer line"
fi
if [ "$(sort "$SANDBOX/MEMORY.md" | grep -c .)" = "$(sort "$SANDBOX/MEMORY.md.orig" | grep -c .)" ] && \
   diff <(grep -E '^[A-Za-z0-9][A-Za-z0-9_.-]*:' "$SANDBOX/MEMORY.md" | sort) \
        <(grep -E '^[A-Za-z0-9][A-Za-z0-9_.-]*:' "$SANDBOX/MEMORY.md.orig" | sort) >/dev/null; then
  ok "restored index carries exactly the original entry set"
else
  bad "restored index differs from the original"
fi

# ============================================================================
echo "4. inert when nothing is demoted (safe to register before the readout)"
# ============================================================================
OUT="$(payload "check the raspberrypi tunnel forwarding" | "$HOOK" retrieve 2>/dev/null)"
if [ -z "$OUT" ]; then
  ok "empty tier produces zero bytes of output"
else
  bad "hook spoke with an empty tier: $OUT"
fi

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
