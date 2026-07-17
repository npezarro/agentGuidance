#!/usr/bin/env python3
"""parity-arm-analyzer.py -- readout for the interactive parity-layer A/B.

Joins ~/.claude/parity-telemetry/interactive-arms.jsonl (arm assignments written by
hooks/parity-layer-injection.sh) to the local session transcripts and compares the
layer vs control arms on correction-rate proxies, with the hygiene rules that the
first manual readout (2026-07-16) proved necessary:

  - dedupe by session_id (resume writes a second telemetry row)
  - drop rows with an empty session_id (unjoinable; the hook defaults them to "layer")
  - VERIFY THE MODEL FROM THE TRANSCRIPT, not the arm log: a mid-session /model switch
    is invisible to the SessionStart hook (found in the wild: a "control opus" session
    that actually ran Fable). Non-Opus sessions are excluded as contaminated.
  - drop degenerate sessions (zero assistant turns)
  - exclude non-prompts from the denominator: /commands, <command...>, hook
    <system-reminder>s, <local-command-stdout>, <task-notification>, [Request ...]

Correction metric: PRE-REGISTERED regex below, calibrated once on the sessions
logged through 2026-07-16 and then frozen. Do not tune it mid-test; if it must
change, bump METRIC_VERSION and treat prior readouts as a different metric.
For a higher-quality readout, use --dump-prompts to emit an arm-blind prompt list,
judge each session's corrections manually (or via claude -p), and feed the counts
back with --judgments.

Usage:
  parity-arm-analyzer.py                 # stats readout (regex metric)
  parity-arm-analyzer.py --dump-prompts  # arm-blind prompt dump for manual judging
  parity-arm-analyzer.py --judgments f.jsonl   # override counts with judged ones
                                               # ({"session_id","corrections","prompts"})

Exit codes: 0 ok; 3 telemetry stale >7 days (dead-man; also printed loudly).
"""
import argparse, glob, json, os, re, sys
from datetime import datetime, timezone
from math import comb, sqrt

TELEMETRY = os.environ.get(
    "PARITY_TELEMETRY_FILE",
    os.path.expanduser("~/.claude/parity-telemetry/interactive-arms.jsonl"),
)
PROJECTS_GLOB = os.path.expanduser("~/.claude/projects/*/*.jsonl")
STALE_DAYS = 7

METRIC_VERSION = "corr-regex-v1"  # frozen 2026-07-16; see module docstring
CORRECTION = re.compile(
    r"that'?s (not|wrong)|still (broken|not)|(doesn|didn|isn)'?t work|you didn'?t"
    r"|you missed|i don'?t see|not what i (asked|meant|wanted)|try again|\bundo\b"
    r"|\brevert\b|\bwrong\b|double.count|sort that out|\bfix (it|that)\b"
    r"|you need to (add|fix|change)|mostly good but|why (did|didn'?t) you"
    r"|(that|it) failed|\bagain\b.*\b(broken|error|missing)\b",
    re.I,
)
PRAISE = re.compile(
    r"\bperfect\b|\bthanks\b|\bthank you\b|works now|looks good|\bgreat\b|\bnice\b",
    re.I,
)
NON_PROMPT = ("<command", "<system-reminder", "<local-command-stdout", "<task-notification", "[Request")


def load_arms():
    arms, order = {}, []
    with open(TELEMETRY) as f:
        for line in f:
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            sid = r.get("session_id") or ""
            if not sid:
                continue  # unjoinable
            if sid not in arms:
                arms[sid] = r
                order.append(sid)
    return arms, order


def newest_ts():
    ts = None
    with open(TELEMETRY) as f:
        for line in f:
            try:
                ts = json.loads(line).get("ts") or ts
            except json.JSONDecodeError:
                pass
    return ts


def prompt_text(msg):
    c = msg.get("message", {}).get("content")
    if isinstance(c, str):
        return c.strip()
    if isinstance(c, list):
        return " ".join(
            x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text"
        ).strip()
    return ""


def score_session(path):
    prompts = corr = praise = aturns = out_tok = 0
    models = set()
    with open(path) as f:
        for line in f:
            try:
                m = json.loads(line)
            except json.JSONDecodeError:
                continue
            t = m.get("type")
            if t == "user" and not m.get("isMeta"):
                txt = prompt_text(m)
                if not txt or txt.startswith("/") or any(s in txt[:60] for s in NON_PROMPT):
                    continue
                prompts += 1
                head = txt[:200]
                if CORRECTION.search(head):
                    corr += 1
                elif PRAISE.search(head):
                    praise += 1
            elif t == "assistant":
                mm = m.get("message", {})
                mod = mm.get("model", "")
                if mod and mod != "<synthetic>":
                    models.add(mod)
                    aturns += 1
                out_tok += (mm.get("usage") or {}).get("output_tokens", 0)
    return dict(prompts=prompts, corr=corr, praise=praise, aturns=aturns,
                out_tok=out_tok, models=sorted(models))


def fisher_two_sided(a, b, c, d):
    n, r1, c1 = a + b + c + d, a + b, a + c
    if n == 0 or comb(n, r1) == 0:
        return 1.0
    def p(x):
        return comb(c1, x) * comb(n - c1, r1 - x) / comb(n, r1)
    p0 = p(a)
    return min(1.0, sum(p(x) for x in range(max(0, r1 + c1 - n), min(r1, c1) + 1) if p(x) <= p0 + 1e-12))


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 1.0)
    ph, d = k / n, 1 + z * z / n
    ctr = (ph + z * z / (2 * n)) / d
    w = z * sqrt(ph * (1 - ph) / n + z * z / (4 * n * n)) / d
    return (max(0.0, ctr - w), min(1.0, ctr + w))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump-prompts", action="store_true", help="arm-blind prompt dump for judging")
    ap.add_argument("--judgments", help="JSONL of {session_id, corrections, prompts} overriding regex counts")
    args = ap.parse_args()

    if not os.path.exists(TELEMETRY):
        print(f"no telemetry file at {TELEMETRY}", file=sys.stderr)
        return 1

    arms, order = load_arms()
    transcripts = {
        os.path.basename(p)[:-6]: p for p in glob.glob(PROJECTS_GLOB)
        if os.path.basename(p)[:-6] in arms
    }

    # dead-man: the test silently dies if the hook breaks or the default model
    # leaves Opus; surface that before any stats
    stale = False
    ts = newest_ts()
    if ts:
        age = (datetime.now(timezone.utc) - datetime.fromisoformat(ts.replace("Z", "+00:00"))).days
        if age >= STALE_DAYS:
            stale = True
            print(f"⚠️  DEAD-MAN: no new arm telemetry for {age} days (last {ts}). "
                  f"Hook broken, or WSL default model is not Opus — the A/B is not accruing.")

    judged = {}
    if args.judgments:
        with open(args.judgments) as f:
            for line in f:
                try:
                    j = json.loads(line)
                    judged[j["session_id"]] = j
                except (json.JSONDecodeError, KeyError):
                    continue

    rows, excluded = [], []
    for sid in order:
        arm = arms[sid]["arm"]
        path = transcripts.get(sid)
        if not path:
            excluded.append((sid, arm, "transcript rotated/missing"))
            continue
        s = score_session(path)
        if s["aturns"] == 0:
            excluded.append((sid, arm, "degenerate (0 assistant turns)"))
            continue
        if not any("opus" in m.lower() for m in s["models"]):
            excluded.append((sid, arm, f"CONTAMINATED: ran {','.join(s['models'])}"))
            continue
        if sid in judged:
            s["corr"] = judged[sid].get("corrections", s["corr"])
            s["prompts"] = judged[sid].get("prompts", s["prompts"])
            s["judged"] = True
        rows.append((sid, arm, s))

    if args.dump_prompts:
        # arm-blind: no arm labels, so a human/LLM judge can't be biased by assignment
        for sid, _arm, _s in rows:
            print(f"\n===== session {sid} =====")
            i = 0
            with open(transcripts[sid]) as f:
                for line in f:
                    try:
                        m = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if m.get("type") != "user" or m.get("isMeta"):
                        continue
                    txt = prompt_text(m)
                    if not txt or txt.startswith("/") or any(x in txt[:60] for x in NON_PROMPT):
                        continue
                    i += 1
                    print(f"  [{i}] {txt[:300]}")
        return 0

    metric = f"judged ({len(judged)} sessions)" if judged else METRIC_VERSION
    print(f"\nparity interactive A/B readout — metric: {metric}")
    print(f"telemetry: {len(arms)} unique sessions; usable: {len(rows)}; excluded: {len(excluded)}")
    for sid, arm, why in excluded:
        print(f"  excluded {arm:7s} {sid[:8]}: {why}")

    agg = {"layer": dict(sess=0, sess_corr=0, prompts=0, corr=0, tok=0),
           "control": dict(sess=0, sess_corr=0, prompts=0, corr=0, tok=0)}
    print(f"\n{'arm':7s} {'session':8s} {'prompts':>7s} {'corr':>4s} {'turns':>5s} {'out_tok':>8s}  models")
    for sid, arm, s in sorted(rows, key=lambda r: r[1]):
        a = agg[arm]
        a["sess"] += 1
        a["sess_corr"] += 1 if s["corr"] > 0 else 0
        a["prompts"] += s["prompts"]
        a["corr"] += s["corr"]
        a["tok"] += s["out_tok"]
        print(f"{arm:7s} {sid[:8]} {s['prompts']:>7d} {s['corr']:>4d} {s['aturns']:>5d} {s['out_tok']:>8d}  {','.join(s['models'])}")

    L, C = agg["layer"], agg["control"]
    print(f"\n{'':22s}{'layer':>16s} {'control':>16s}")
    print(f"{'sessions':22s}{L['sess']:>16d} {C['sess']:>16d}")
    for name, k_l, n_l, k_c, n_c in (
        ("corrections/prompt", L["corr"], L["prompts"], C["corr"], C["prompts"]),
        ("sessions w/ >=1 corr", L["sess_corr"], L["sess"], C["sess_corr"], C["sess"]),
    ):
        wl, wc = wilson(k_l, n_l), wilson(k_c, n_c)
        p = fisher_two_sided(k_l, n_l - k_l, k_c, n_c - k_c)
        fl = f"{k_l}/{n_l} ({wl[0]:.0%}-{wl[1]:.0%})"
        fc = f"{k_c}/{n_c} ({wc[0]:.0%}-{wc[1]:.0%})"
        print(f"{name:22s}{fl:>16s} {fc:>16s}   Fisher p={p:.3f}")

    n_small = min(L["sess"], C["sess"])
    if n_small < 15:
        print(f"\nNOT READABLE YET: smaller arm has {n_small} sessions; hold conclusions until >=15-30/arm.")
    return 3 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
