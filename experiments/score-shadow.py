#!/usr/bin/env python3
"""Score xp-001 (memory-lazy-tier) from the shadow log.

Joins what the retriever WOULD have surfaced (memory-lazy-shadow.jsonl)
against what sessions ACTUALLY opened (Read tool calls in transcripts).

The decision number is RECALL: of the times a session genuinely wanted a
candidate memory, how often would the keyword retriever have surfaced it?
A demotion is only safe if recall is high. The counterweight is INJECTION
COST: tokens spent surfacing entries nobody went on to use.

Usage:  score-shadow.py [--log PATH] [--since YYYY-MM-DD]
"""
import argparse, collections, glob, json, os, re, sys, time

HOME = os.path.expanduser("~")
ap = argparse.ArgumentParser()
ap.add_argument("--log", default=f"{HOME}/.claude/memory-lazy-shadow.jsonl")
ap.add_argument("--candidates", default=f"{HOME}/.claude/memory-lazy-candidates.txt")
ap.add_argument("--since", default=None, help="YYYY-MM-DD")
args = ap.parse_args()

if not os.path.exists(args.log):
    sys.exit(f"no shadow log yet at {args.log} — the experiment has not collected data")

since_ts = 0
if args.since:
    since_ts = int(time.mktime(time.strptime(args.since, "%Y-%m-%d")))

candidates = set()
if os.path.exists(args.candidates):
    for line in open(args.candidates, encoding="utf-8"):
        if line.strip() and not line.startswith("#"):
            candidates.add(line.split(":")[0].strip())

# --- what the retriever would have surfaced, per session -------------------
would = collections.defaultdict(set)      # session -> {names}
prompts = 0
prompts_with_hit = 0
injections = 0
for line in open(args.log, encoding="utf-8"):
    try:
        r = json.loads(line)
    except Exception:
        continue
    if r.get("ts", 0) < since_ts:
        continue
    prompts += 1
    hits = r.get("would_inject") or []
    if hits:
        prompts_with_hit += 1
        injections += len(hits)
    for h in hits:
        would[r.get("session", "")].add(h["name"])

# --- what sessions actually opened -----------------------------------------
opened = collections.defaultdict(set)     # session -> {names}
for path in glob.glob(f"{HOME}/.claude/projects/*/*.jsonl"):
    sid = os.path.basename(path)[:-6]
    if sid not in would and sid not in opened:
        # Only sessions the shadow log saw are in scope; others predate the test.
        if sid not in would:
            continue
    try:
        with open(path, errors="ignore") as fh:
            for line in fh:
                if '"file_path"' not in line:
                    continue
                for m in re.finditer(r'"file_path":"[^"]*/memory/([^"/]+)\.md"', line):
                    if m.group(1) in candidates:
                        opened[sid].add(m.group(1))
    except OSError:
        continue

# --- score ------------------------------------------------------------------
opportunities = hits_recalled = 0
missed = []
for sid, names in opened.items():
    for n in names:
        opportunities += 1
        if n in would.get(sid, ()):
            hits_recalled += 1
        else:
            missed.append((sid[:8], n))

print(f"prompts observed            : {prompts}")
print(f"prompts with >=1 injection  : {prompts_with_hit}"
      f"  ({prompts_with_hit/prompts*100:.0f}%)" if prompts else "")
print(f"mean injections per prompt  : {injections/prompts:.2f}" if prompts else "")
print(f"candidate set size          : {len(candidates)}")
print()
if opportunities == 0:
    print("RECALL: not yet measurable — no session in the observation window opened")
    print("a candidate memory. Either keep collecting, or take that as evidence the")
    print("candidates are genuinely cold (which is itself the result we are testing for).")
else:
    print(f"opportunities (candidate memory actually opened) : {opportunities}")
    print(f"retriever would have surfaced it                 : {hits_recalled}"
          f"  ({hits_recalled/opportunities*100:.0f}% RECALL)")
    if missed:
        print("\n  misses (session, memory):")
        for s, n in missed[:15]:
            print(f"    {s}  {n}")

print("\nDecision rule (xp-001): ship the lazy tier if recall >= 80% AND mean")
print("injections per prompt <= 1.0. Below 80%, the demotion costs more recall")
print("than the ~500 tokens it saves is worth.")
