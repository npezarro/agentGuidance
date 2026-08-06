#!/usr/bin/env bash
# memory-lazy-shadow.sh — UserPromptSubmit hook, SHADOW MODE ONLY.
#
# Experiment: xp-001 (memory-lazy-tier). Question: if we demote never-read
# reference-shaped memories out of the always-loaded index and retrieve them
# on demand by keyword, do we lose recall?
#
# This hook answers that WITHOUT taking the risk. It changes nothing:
#   - it prints NOTHING to stdout, so it adds zero context and zero behaviour
#   - nothing is demoted; the full index stays loaded exactly as it is today
#   - it only RECORDS which candidate entries a keyword matcher WOULD have
#     surfaced for this prompt
#
# Later, score-shadow.py joins this log against the memories the session
# actually opened (Read tool calls in the transcript). That yields the number
# the decision needs: of the times a candidate memory was genuinely wanted,
# how often would the retriever have surfaced it first?
#
# PRIVACY: the log records matched memory NAMES, scores, and the prompt's
# LENGTH. It never records prompt text, so the log carries nothing sensitive
# and lives outside every git repo.
#
# Install (settings.json UserPromptSubmit):
#   { "type": "command",
#     "command": "bash -c 'printf \"%s\" \"$(cat)\" | $HOME/repos/agentGuidance/experiments/memory-lazy-shadow.sh; exit 0'" }
#
# Fail-open: any error exits 0 silently. A measurement rig must never be able
# to break the thing it is measuring.

set -uo pipefail

LOG="${MEMORY_LAZY_SHADOW_LOG:-$HOME/.claude/memory-lazy-shadow.jsonl}"
CANDIDATES="${MEMORY_LAZY_CANDIDATES:-$HOME/.claude/memory-lazy-candidates.txt}"
# Scored against EVERY index entry; the candidates file only tags which hits
# belong to the demote tier, so cost and recall can be read off separately.
INDEX_SET="${MEMORY_LAZY_INDEX:-$HOME/.claude/memory-lazy-index.txt}"
TOP_K="${MEMORY_LAZY_TOP_K:-2}"   # tightened from 3: a third-best guess was rarely the wanted one
MIN_SCORE="${MEMORY_LAZY_MIN_SCORE:-2}"

[ -f "$CANDIDATES" ] || exit 0
[ -f "$INDEX_SET" ] || INDEX_SET="$CANDIDATES"

input="$(cat)" || exit 0
[ -n "$input" ] || exit 0

# The payload goes in by ENV, not stdin: stdin is already carrying the python
# script via the heredoc, and a second redirection would silently feed the JSON
# in as the program text.
RIG_SRC="${BASH_SOURCE[0]:-$0}" HOOK_INPUT="$input" LOG="$LOG" CANDIDATES="$CANDIDATES" INDEX_SET="$INDEX_SET" TOP_K="$TOP_K" MIN_SCORE="$MIN_SCORE" \
python3 - <<'PY' 2>/dev/null || exit 0
import json, os, re, sys, time

log_path = os.environ["LOG"]
cand_path = os.environ["CANDIDATES"]
index_path = os.environ.get("INDEX_SET") or cand_path
top_k = int(os.environ["TOP_K"])
min_score = float(os.environ["MIN_SCORE"])  # scores are now IDF-weighted floats

raw = os.environ.get("HOOK_INPUT", "")
try:
    payload = json.loads(raw)
except Exception:
    payload = {}
prompt = payload.get("prompt") or payload.get("user_prompt") or ""
if not prompt:
    sys.exit(0)
session = payload.get("session_id") or payload.get("sessionId") or ""
cwd = payload.get("cwd") or ""

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


# Load candidates once and measure how many of them each token appears in. A
# token common across the set says almost nothing about WHICH candidate is
# relevant, so it is down-weighted, and dropped outright past a quarter of the
# set. This re-derives from whatever the candidate set happens to be, instead
# of a hand-kept stoplist that rots as memories are added.
cand_names = set()
for line in open(cand_path, encoding="utf-8"):
    if line.strip() and not line.startswith("#"):
        cand_names.add(line.split(":")[0].strip())

cands = []
for line in open(index_path, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    name, _, hook = line.partition(": ")
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
# Collapsed form catches names that fuse words the prompt separates
# ("raspberrypi" vs "raspberry pi"), which a pure token match misses.
p_collapsed = re.sub(r"[^a-z0-9]", "", prompt.lower())

scored = []
for name, name_t, hook_t, bare in cands:
    # Name tokens are the strong signal; hook tokens are corroborating.
    score = (sum(weight(t, 2.0) for t in name_t & pt)
             + sum(weight(t, 1.0) for t in hook_t & pt))
    stem = re.sub(r"[^a-z0-9]", "", bare)
    if len(stem) > 5 and stem in p_collapsed:
        score += 3.0                      # whole-name substring: high precision
    if score >= min_score:
        scored.append((round(score, 2), name))

scored.sort(reverse=True)
# Relative-margin cut: when one candidate clearly wins, a much weaker runner-up
# is a guess, not a second answer, and it costs tokens plus context noise to
# show it. Self-tuning, unlike a hand-set stoplist of generic verbs, which is
# what would otherwise be needed to stop "update the housing scout" from
# dragging in reference_cc_wsl_update behind the obvious winner.
if scored:
    top = scored[0][0]
    scored = [x for x in scored if x[0] >= 0.4 * top]
hits = [{"name": n, "score": s, "cand": n in cand_names} for s, n in scored[:top_k]]

# RIG VERSION STAMP. Every record carries a fingerprint of the configuration
# that produced it: matcher source, scoring set, candidate set, and thresholds.
# Without this, changing the rig silently mixes incompatible records into one
# log and the scorer averages across them. That is not hypothetical: on
# 2026-08-05 this log accumulated records under four configurations in a single
# day and produced a 0% recall figure that was an artifact of the mixing, not a
# property of the retriever. A stamp makes that visible instead of invisible.
import hashlib
_h = hashlib.sha256()
try:
    _h.update(open(os.environ["RIG_SRC"], "rb").read())   # the matcher itself
except (OSError, KeyError):
    pass
for _p in (index_path, cand_path):
    try:
        _h.update(open(_p, "rb").read())
    except OSError:
        pass
_h.update(f"{top_k}|{min_score}".encode())
rig = _h.hexdigest()[:12]

rec = {
    "rig": rig,
    "ts": int(time.time()),
    "session": session,
    "cwd": cwd,
    "prompt_len": len(prompt),
    "scored_against": len(cands),
    "candidate_set": len(cand_names),
    "would_inject": hits,
}
try:
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec) + "\n")
except OSError:
    pass
PY
exit 0
