#!/usr/bin/env python3
"""Score xp-001 (memory-lazy-tier) from the shadow log.

Two questions, deliberately measured on different populations:

  RECALL (does keyword retrieval work at all?) is measured over EVERY index
  entry, because that is the only population where the event is observable.
  The demote candidates were selected for having zero reads, so measuring
  recall on them alone is circular: the observed rate of "a candidate was
  opened" is 0 across 4,225 sessions, and 14 more days would not change that.
  Retrieval quality on memories that DO get opened is the transferable signal.

  COST (what would the lazy tier actually inject?) is measured on the candidate
  subset only, since those are the entries that would move out of the index.

Sessions are segmented interactive vs headless. ~140 of ~172 daily sessions are
cron (fix-checker, learning-agent, autonomousDev) and their prompts are machine
text; pooling them would let bot traffic decide a question about Nick's context.

Usage:  score-shadow.py [--log PATH] [--since YYYY-MM-DD]
"""
import argparse, collections, glob, json, os, re, sys, time

HOME = os.path.expanduser("~")
ap = argparse.ArgumentParser()
ap.add_argument("--log", default=f"{HOME}/.claude/memory-lazy-shadow.jsonl")
ap.add_argument("--candidates", default=f"{HOME}/.claude/memory-lazy-candidates.txt")
ap.add_argument("--index", default=f"{HOME}/.claude/memory-lazy-index.txt")
ap.add_argument("--since", default=None, help="YYYY-MM-DD")
args = ap.parse_args()

if not os.path.exists(args.log):
    sys.exit(f"no shadow log at {args.log} — the experiment has not collected data")

since_ts = 0
if args.since:
    since_ts = int(time.mktime(time.strptime(args.since, "%Y-%m-%d")))

candidates = set()
if os.path.exists(args.candidates):
    for line in open(args.candidates, encoding="utf-8"):
        if line.strip() and not line.startswith("#"):
            candidates.add(line.split(":")[0].strip())

# The scoring set is frozen at test start. A memory created DURING the window is
# not in it, so the retriever never had a chance at it; counting such an open as
# a miss would bias recall downward and could wrongly condemn the retriever.
scoring_set = set()
if os.path.exists(args.index):
    for line in open(args.index, encoding="utf-8"):
        if line.strip() and not line.startswith("#"):
            scoring_set.add(line.split(":")[0].strip())

HEADLESS = ("fix-checker", "autonomousDev", "learning", "job-pipeline", "scripts")


def is_headless(cwd):
    return any(h in (cwd or "") for h in HEADLESS)


# --- what the retriever would have surfaced -------------------------------
would = collections.defaultdict(set)          # session -> {names}
seg = {"interactive": collections.Counter(), "headless": collections.Counter()}
sess_cwd = {}
for line in open(args.log, encoding="utf-8"):
    try:
        r = json.loads(line)
    except Exception:
        continue
    if r.get("ts", 0) < since_ts:
        continue
    k = "headless" if is_headless(r.get("cwd")) else "interactive"
    sid = r.get("session", "")
    sess_cwd[sid] = r.get("cwd", "")
    hits = r.get("would_inject") or []
    cand_hits = [h for h in hits if h.get("cand")]
    seg[k]["prompts"] += 1
    seg[k]["injections_all"] += len(hits)
    seg[k]["injections_cand"] += len(cand_hits)
    seg[k]["prompts_with_cand"] += 1 if cand_hits else 0
    for h in hits:
        would[sid].add(h["name"])

# --- what sessions actually opened ----------------------------------------
# NOTE (2026-08-05): a previous pass tried to add "the harness auto-recalled it
# into a system-reminder" as a second usage channel. That was an ARTIFACT and is
# deliberately not here. 91 of 99 matching reminder blocks were inside
# "type":"tool_result" — they are the staleness notice appended to a Read, and
# the memory names inside them are the read file's own [[wikilinks]], not
# independent evidence that another memory was wanted. Acting on it wrongly
# excluded 7 entries from the candidate set. A Read is the usage signal.
opened = collections.defaultdict(set)
resolved = 0
for path in glob.glob(f"{HOME}/.claude/projects/*/*.jsonl"):
    sid = os.path.basename(path)[:-6]
    if sid not in would:
        continue                     # only sessions the shadow log observed
    resolved += 1
    try:
        with open(path, errors="ignore") as fh:
            for line in fh:
                if '"file_path"' not in line:
                    continue
                for m in re.finditer(r'"file_path":"[^"]*/memory/([^"/]+)\.md"', line):
                    if m.group(1) != "MEMORY":
                        opened[sid].add(m.group(1))
    except OSError:
        continue

# --- report ----------------------------------------------------------------
print("=" * 66)
print("COST — what the lazy tier would inject (candidate subset only)")
print("=" * 66)
for k in ("interactive", "headless"):
    s = seg[k]
    n = s["prompts"]
    if not n:
        print(f"  {k:12} no prompts observed")
        continue
    print(f"  {k:12} {n:5} prompts | {s['injections_cand']/n:.2f} cand-injections/prompt"
          f" | {s['prompts_with_cand']/n*100:4.0f}% of prompts hit"
          f" | (all-index {s['injections_all']/n:.2f})")
print("\n  Decision-rule ceiling: <= 1.00 cand-injections/prompt (INTERACTIVE).")

print()
print("=" * 66)
print("RECALL — when a memory was opened, was it in the retriever's top-k?")
print("=" * 66)
opp = hit = out_of_set = 0
missed = []
for sid, names in opened.items():
    for n in names:
        if scoring_set and n not in scoring_set:
            out_of_set += 1      # created after the set was frozen; not scoreable
            continue
        opp += 1
        if n in would.get(sid, ()):
            hit += 1
        else:
            missed.append((sid[:8], n, sess_cwd.get(sid, "")[:40]))
# A broken join and genuine no-demand both render as "0 opportunities" and imply
# OPPOSITE decisions, so join health is reported rather than assumed.
join_rate = resolved / len(would) if would else 0
print(f"  sessions observed: {len(would)}, transcripts resolved: {resolved}"
      f" ({join_rate*100:.0f}%)"
      + ("   *** JOIN LOOKS BROKEN — the 0 below is NOT evidence of no demand ***"
         if would and join_rate < 0.5 else ""))
if opp == 0:
    print("  0 opportunities: no observed session opened any memory file yet.")
    print("  Keep collecting. ~3.7% of sessions historically open one, so expect")
    print("  roughly 1 opportunity per 27 sessions observed.")
else:
    print(f"  opportunities (a memory was opened) : {opp}")
    if out_of_set:
        print(f"  excluded (created after freeze)     : {out_of_set}")
    print(f"  retriever had it in top-k           : {hit}  ({hit/opp*100:.0f}% RECALL)")
    if missed:
        print("\n  misses:")
        for s, n, c in missed[:15]:
            print(f"    {s}  {n:45} {c}")

print()
print("=" * 66)
print("CANDIDATE DEMAND — the 45 entries proposed for demotion")
print("=" * 66)
cand_opened = sum(1 for names in opened.values() for n in names if n in candidates)
print(f"  times a demote-candidate was opened in the observed window: {cand_opened}")
print("  Pre-committed reading (set 2026-08-05, before data): zero demand across")
print("  4,225 historical sessions PLUS the observation window is EVIDENCE of no")
print("  demand, not a failed measurement. If cand_opened is 0 and interactive")
print("  RECALL >= 80%, ship the demotion. If RECALL < 80%, the retriever is not")
print("  good enough to be the safety net, so keep the entries loaded regardless")
print("  of how cold they look.")

# --- collector liveness ----------------------------------------------------
age_h = (time.time() - os.path.getmtime(args.log)) / 3600
print()
print(f"collector: log last written {age_h:.1f}h ago"
      + ("  <-- STALE, the hook may be broken" if age_h > 24 else ""))
