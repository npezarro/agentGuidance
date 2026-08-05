#!/usr/bin/env bash
# xp001-progress.sh — one-line liveness for the xp-001 shadow collector.
#
# Wired in as xp-001's `progress_cmd`, so it appears in the daily #experiments
# post and on the dashboard.
#
# It reports STALENESS, not just a count. A count alone is the failure mode this
# is meant to catch: if the hook breaks on day 2, "1,240 prompts observed" keeps
# printing every day and looks healthy, because a frozen number and a growing
# one read identically in a daily digest. The age of the last write is what
# distinguishes them.
set -uo pipefail

LOG="${MEMORY_LAZY_SHADOW_LOG:-$HOME/.claude/memory-lazy-shadow.jsonl}"

if [ ! -f "$LOG" ]; then
  echo "NO DATA — shadow log missing (hook not firing?)"
  exit 0
fi

LOG="$LOG" python3 - <<'PY'
import json, os, time

path = os.environ["LOG"]
n = interactive = cand_inj = opps = 0
last = 0
HEADLESS = ("fix-checker", "autonomousDev", "learning", "job-pipeline", "scripts")
for line in open(path, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        r = json.loads(line)
    except Exception:
        continue
    n += 1
    last = max(last, r.get("ts", 0))
    if not any(h in (r.get("cwd") or "") for h in HEADLESS):
        interactive += 1
        cand_inj += sum(1 for h in (r.get("would_inject") or []) if h.get("cand"))

age_h = (time.time() - last) / 3600 if last else 999
rate = f"{cand_inj/interactive:.2f}" if interactive else "n/a"
msg = f"{n} prompts ({interactive} interactive), {rate} cand-inj/prompt"
if age_h > 24:
    msg += f"  ⚠ STALE: no data for {age_h:.0f}h, hook may be broken"
elif age_h > 6:
    msg += f"  (last write {age_h:.0f}h ago)"
print(msg)
PY
