#!/usr/bin/env bash
# verify-report.sh — fresh-context verifier pass over a finished workspace.
#
# Spawns a read+execute-only agent (no Write/Edit) that re-runs the project's
# checks (tests, demo commands) and emits an EVIDENCE BLOCK: verbatim outputs in
# fenced code plus one-line verdicts. Append its output to the worker's final
# report, or diff it against the worker's claims.
#
# Rationale: separate fresh-context verifiers outperform self-critique, and the
# 2026-07-06 parity audit showed the residual Opus gap is evidence surviving
# into the final report — this generates that evidence deterministically.
#
# Usage: verify-report.sh <workspace-dir> ["task context"] [--model M]
set -euo pipefail

WS="${1:?Usage: verify-report.sh <workspace-dir> [\"task context\"] [--model M]}"
shift
CONTEXT=""
MODEL="claude-sonnet-4-6"
while [ $# -gt 0 ]; do
    case "$1" in
        --model) MODEL="$2"; shift 2 ;;
        *)       CONTEXT="$1"; shift ;;
    esac
done
[ -d "$WS" ] || { echo "not a directory: $WS" >&2; exit 1; }

PROMPT="You are a verification agent with a fresh context: you did NOT do the work in this directory and must trust nothing about it. Your only job is to produce an EVIDENCE BLOCK for a status report.

1. Discover the project's checks: test suites, build commands, demo/CLI entry points (read README, look for test files).
2. Run each check and capture the verbatim output. Run test suites twice if a failure looks intermittent.
3. Output ONLY the evidence block, in this exact shape:
   - one fenced code block per check, containing the command and its verbatim output
   - after each block, one line: VERIFIED: <what this proves> or NOT VERIFIED: <what could not be confirmed and why>
   - final line: SUMMARY: <n> checks run, <n> verified, <n> failed/unverifiable
Do not editorialize, do not fix anything, do not modify any file.${CONTEXT:+

Task context: $CONTEXT}"

cd "$WS"
claude --print --max-turns 25 --output-format json \
    --dangerously-skip-permissions --model "$MODEL" \
    --allowedTools "Bash,Read,Glob,Grep" \
    -p "$PROMPT" | jq -r '.result // "VERIFIER FAILED: no result"'
