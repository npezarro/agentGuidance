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
import argparse, collections, datetime, glob, json, os, re, sys, time

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
rigs = collections.Counter()
would = collections.defaultdict(set)          # session -> {names}
sess_first_ts = {}                            # session -> ts of its FIRST surviving record
seg = {"interactive": collections.Counter(), "headless": collections.Counter()}
sess_cwd = {}
for line in open(args.log, encoding="utf-8"):
    try:
        r = json.loads(line)
    except Exception:
        continue
    if r.get("ts", 0) < since_ts:
        continue
    rigs[r.get("rig", "unstamped")] += 1
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
    sess_first_ts[sid] = min(sess_first_ts.get(sid, r["ts"]), r["ts"])

# --- what sessions actually opened ----------------------------------------
# NOTE (2026-08-05): a previous pass tried to add "the harness auto-recalled it
# into a system-reminder" as a second usage channel. That was an ARTIFACT and is
# deliberately not here. 91 of 99 matching reminder blocks were inside
# "type":"tool_result" — they are the staleness notice appended to a Read, and
# the memory names inside them are the read file's own [[wikilinks]], not
# independent evidence that another memory was wanted. Acting on it wrongly
# excluded 7 entries from the candidate set. A Read is the usage signal.
#
# TIME BOUND (2026-08-07). Both sides of this join must cover the same window or
# the comparison is rigged. `would[sid]` can only contain prompts recorded in THIS
# log, which begins where the log was last archived at the rig freeze — not when
# the session started. A memory opened before that point had its triggering prompt
# recorded under a DIFFERENT matcher (v1/v2/v3-mixed), so scoring it here is a
# guaranteed miss no retriever could ever win. Four of eight opportunities were
# exactly that: one 3-day session with 6 records archived and 1 surviving.
#
# The bound is PER SESSION, not the log's global start: for a session whose first
# surviving record is at 20:39, an open at 18:00 is still unwinnable even though
# the log itself opened at 17:47.
#
# Deliberately NOT fixed by reading the archives instead — they are unstamped and
# were produced by four different matchers, and this scorer refuses to mix rigs.
# Censoring is not symmetric: it can only push recall DOWN, so it manufactures
# false negatives against a rule whose failure branch is "recall < 80% -> do not
# ship". Both readings are printed so the correction stays auditable.
_TS_RE = re.compile(r'"timestamp":"([^"]+)"')


def _epoch(line):
    m = _TS_RE.search(line)
    if not m:
        return None
    try:
        return datetime.datetime.fromisoformat(
            m.group(1).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


# Three bounds, three purposes — do not collapse them:
#   opened           per-session floor -> RECALL. Fair to the retriever: only score
#                    opens whose triggering prompt this rig actually saw.
#   opened_window    log's global start -> DEMAND. "Did anyone want a candidate
#                    during the observation period?" is a question about Nick, not
#                    about the retriever, so the per-session floor is too strict
#                    here and would UNDER-count demand — which biases toward
#                    shipping, the dangerous direction for this decision.
#   opened_unbounded no bound -> audit only, so the correction is visible.
log_start = min(sess_first_ts.values()) if sess_first_ts else 0
opened = collections.defaultdict(set)
opened_window = collections.defaultdict(set)
opened_unbounded = collections.defaultdict(set)
undateable = 0
resolved = 0
for path in glob.glob(f"{HOME}/.claude/projects/*/*.jsonl"):
    sid = os.path.basename(path)[:-6]
    if sid not in would:
        continue                     # only sessions the shadow log observed
    resolved += 1
    floor = sess_first_ts.get(sid)
    try:
        with open(path, errors="ignore") as fh:
            for line in fh:
                if '"file_path"' not in line:
                    continue
                names = [m.group(1) for m in
                         re.finditer(r'"file_path":"[^"]*/memory/([^"/]+)\.md"', line)
                         if m.group(1) != "MEMORY"]
                if not names:
                    continue
                opened_unbounded[sid].update(names)
                ts = _epoch(line)
                if ts is None:
                    undateable += len(names)
                    continue         # cannot place it in the window; do not score it
                if ts >= log_start:
                    opened_window[sid].update(names)
                if floor is not None and ts < floor:
                    continue         # its prompt was recorded under an older rig
                opened[sid].update(names)
    except OSError:
        continue

# --- report ----------------------------------------------------------------
if len(rigs) > 1:
    print("!" * 66)
    print("MIXED RIG VERSIONS IN THIS LOG — the numbers below average across")
    print("configurations that are not comparable. Do not decide from them.")
    for r_, n_ in rigs.most_common():
        print(f"   {r_}: {n_} records")
    print("Reset the log (archive it) and collect under one frozen rig.")
    print("!" * 66)
    print()

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
def tally(src):
    """-> (opportunities, hits, out_of_set, [misses])"""
    o = h = oos = 0
    ms = []
    for sid, names in src.items():
        for n in names:
            if scoring_set and n not in scoring_set:
                oos += 1         # created after the set was frozen; not scoreable
                continue
            o += 1
            if n in would.get(sid, ()):
                h += 1
            else:
                ms.append((sid[:8], n, sess_cwd.get(sid, "")[:40]))
    return o, h, oos, ms


opp, hit, out_of_set, missed = tally(opened)
opp_u, hit_u, _, _ = tally(opened_unbounded)
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
    if undateable:
        print(f"  excluded (no timestamp to place)    : {undateable}")
    print(f"  retriever had it in top-k           : {hit}  ({hit/opp*100:.0f}% RECALL)")
    dropped = opp_u - opp
    if dropped:
        print(f"\n  time bound dropped {dropped} unwinnable opportunit"
              f"{'y' if dropped == 1 else 'ies'} whose triggering prompt was")
        print(f"  recorded under an archived rig. Pre-fix reading was "
              f"{hit_u}/{opp_u} = {hit_u/max(opp_u,1)*100:.0f}%; both are shown so the")
        print("  correction stays auditable. Censoring only ever pushes recall DOWN.")
    if opp < 15:
        print(f"\n  *** n={opp}. Too few opportunities to decide anything. The 80% bar")
        print("      is not meaningfully testable at this sample size. ***")
    if missed:
        print("\n  misses:")
        for s, n, c in missed[:15]:
            print(f"    {s}  {n:45} {c}")

print()
print("=" * 66)
print("CANDIDATE DEMAND — the 45 entries proposed for demotion")
print("=" * 66)
# Demand uses the OBSERVATION-WINDOW bound, not the per-session recall floor: a
# candidate that was wanted is a fact about demand even on a prompt this rig did
# not record. Using the stricter floor here would under-count demand, and the
# decision rule ships on cand_opened == 0 — so that error points the wrong way.
cand_opened = sum(1 for names in opened_window.values() for n in names if n in candidates)
cand_recall_bound = sum(1 for names in opened.values() for n in names if n in candidates)
print(f"  times a demote-candidate was opened in the observed window: {cand_opened}")
if cand_opened != cand_recall_bound:
    print(f"  (recall-bounded view would have said {cand_recall_bound} — demand is"
          " deliberately measured on the wider window)")
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
