#!/usr/bin/env bash
# bestof-claude.sh — run the same prompt on N parallel Opus instances in cloned
# workspaces, judge the final reports with a cheap model, emit the winner.
#
# Rationale (2026-07-06 fable-opus parity audit): report quality is stochastic in
# both Opus and Fable (same probe scored 8,7,9 across runs). Patched Opus costs
# ~half a Fable run, so best-of-2 Opus ≈ Fable cost with better reliability.
#
# Usage:
#   bestof-claude.sh [-n N] [--model M] [--judge-model J] [--workdir DIR]
#                    [--max-turns T] "PROMPT"
# Output: winner's final report on stdout; winner workspace path on stderr.
set -euo pipefail

N=2
MODEL="claude-opus-4-8"
JUDGE_MODEL="claude-haiku-4-5"
WORKDIR=""
MAX_TURNS=45
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        -n)            N="$2"; shift 2 ;;
        --model)       MODEL="$2"; shift 2 ;;
        --judge-model) JUDGE_MODEL="$2"; shift 2 ;;
        --workdir)     WORKDIR="$2"; shift 2 ;;
        --max-turns)   MAX_TURNS="$2"; shift 2 ;;
        *)             PROMPT="$1"; shift ;;
    esac
done
[ -n "$PROMPT" ] || { echo "Usage: bestof-claude.sh [opts] \"PROMPT\"" >&2; exit 1; }

RUN_ROOT="$(mktemp -d /tmp/bestof.XXXXXX)"
declare -a PIDS DIRS

for i in $(seq 1 "$N"); do
    D="$RUN_ROOT/arm$i"
    mkdir -p "$D"
    if [ -n "$WORKDIR" ]; then
        cp -r "$WORKDIR/." "$D/"
    fi
    DIRS+=("$D")
    (
        cd "$D"
        EFFORT_ARGS=()
        [ -n "${BAKE_EFFORT:-}" ] && EFFORT_ARGS=(--effort "$BAKE_EFFORT")
        claude --print --max-turns "$MAX_TURNS" --output-format json \
            --dangerously-skip-permissions --model "$MODEL" "${EFFORT_ARGS[@]}" \
            -p "$PROMPT" > "$RUN_ROOT/arm$i.json" 2>"$RUN_ROOT/arm$i.err" || true
    ) &
    PIDS+=($!)
done
wait "${PIDS[@]}" 2>/dev/null || true

# Collect final reports; drop failed arms.
CANDIDATES=()
for i in $(seq 1 "$N"); do
    R=$(jq -r 'select(.is_error != true) | .result // empty' "$RUN_ROOT/arm$i.json" 2>/dev/null || true)
    [ -n "$R" ] && CANDIDATES+=("$i")
done
if [ "${#CANDIDATES[@]}" -eq 0 ]; then
    echo "bestof: all arms failed (see $RUN_ROOT/arm*.err)" >&2; exit 1
fi
if [ "${#CANDIDATES[@]}" -eq 1 ]; then
    i="${CANDIDATES[0]}"
    jq -r '.result' "$RUN_ROOT/arm$i.json"
    echo "$RUN_ROOT/arm$i" >&2
    exit 0
fi

# Judge: cheap model, blind arm labels, criteria weighted toward evidence fidelity.
JP="You are judging N candidate final reports produced for the same task. Pick the best ONE.

Weigh most heavily: does the report contain verbatim evidence for its claims (pasted command/test output), are all claims scoped to what was actually verified, is it complete against the task, does it lead with the outcome. Penalize dangling references ('output above'), unverified 'green' claims, and unfinished work.

TASK:
$PROMPT
"
for i in "${CANDIDATES[@]}"; do
    JP+="
===== CANDIDATE $i =====
$(jq -r '.result' "$RUN_ROOT/arm$i.json")
"
done
JP+="
Reply with ONLY the winning candidate number (a single integer)."

WINNER=$(claude --print --max-turns 1 --model "$JUDGE_MODEL" -p "$JP" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
case " ${CANDIDATES[*]} " in
    *" $WINNER "*) : ;;
    *) WINNER="${CANDIDATES[0]}" ;;  # judge failed → first successful arm
esac

jq -r '.result' "$RUN_ROOT/arm$WINNER.json"
echo "$RUN_ROOT/arm$WINNER" >&2
