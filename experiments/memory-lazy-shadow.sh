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
TOP_K="${MEMORY_LAZY_TOP_K:-3}"
MIN_SCORE="${MEMORY_LAZY_MIN_SCORE:-2}"

[ -f "$CANDIDATES" ] || exit 0

input="$(cat)" || exit 0
[ -n "$input" ] || exit 0

# The payload goes in by ENV, not stdin: stdin is already carrying the python
# script via the heredoc, and a second redirection would silently feed the JSON
# in as the program text.
HOOK_INPUT="$input" LOG="$LOG" CANDIDATES="$CANDIDATES" TOP_K="$TOP_K" MIN_SCORE="$MIN_SCORE" \
python3 - <<'PY' 2>/dev/null || exit 0
import json, os, re, sys, time

log_path = os.environ["LOG"]
cand_path = os.environ["CANDIDATES"]
top_k = int(os.environ["TOP_K"])
min_score = int(os.environ["MIN_SCORE"])

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

def toks(s):
    return {t for t in re.split(r"[^a-z0-9]+", s.lower()) if len(t) > 3 and t not in STOP}

pt = toks(prompt)
# Collapsed form catches names that fuse words the prompt separates
# ("raspberrypi" vs "raspberry pi"), which a pure token match misses.
p_collapsed = re.sub(r"[^a-z0-9]", "", prompt.lower())

scored = []
for line in open(cand_path, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    name, _, hook = line.partition(": ")
    name_t = toks(name.replace("_", " ").replace("-", " "))
    hook_t = toks(hook)
    # Name tokens are the strong signal; hook tokens are corroborating.
    score = 2 * len(name_t & pt) + len(hook_t & pt)
    stem = re.sub(r"[^a-z0-9]", "", name.lower())
    for prefix in ("project", "reference", "pattern", "feedback", "learning", "rule", "infra", "rollup"):
        if stem.startswith(prefix):
            stem = stem[len(prefix):]
            break
    if len(stem) > 5 and stem in p_collapsed:
        score += 3
    if score >= min_score:
        scored.append((score, name))

scored.sort(reverse=True)
hits = [{"name": n, "score": s} for s, n in scored[:top_k]]

rec = {
    "ts": int(time.time()),
    "session": session,
    "cwd": cwd,
    "prompt_len": len(prompt),
    "candidates_scanned": sum(1 for _ in open(cand_path, encoding="utf-8")),
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
