#!/usr/bin/env bash
# 2-week review of the Opus 5 craft-v1 interactive A/B (treated = minimal report-craft
# rule, control = no injection), set up 2026-07-29 after the bakeoff found the full
# Opus->Fable parity layer counterproductive on Opus 5. Runs the analyzer windowed to
# the cutover, has a fresh Opus 5 review the readout, posts to Discord. Idempotent.
set -uo pipefail

CUTOVER="2026-07-29T23:25:15Z"
MARKER="$HOME/.claude/parity-telemetry/craft-ab-2week-done"
[ -f "$MARKER" ] && exit 0   # already reported (guards the annual cron re-fire)

ANALYZER="$HOME/repos/agentGuidance/scripts/parity-arm-analyzer.py"
READOUT="$(PARITY_SINCE="$CUTOVER" python3 "$ANALYZER" 2>&1 || echo '(analyzer failed)')"

# Best-effort Claude review of the readout (raw readout is the guaranteed payload).
PROMPT="You are reviewing a 2-week interactive A/B on Claude Opus 5. Treated arm = a minimal report-craft instruction rule (craft-v1); control = no injection. Context: a claude-bakeoff run found the full Opus->Fable parity layer counterproductive on Opus 5 (it overshot turn budgets), so we switched to this lightweight rule and are testing whether even it helps. The readout below is a correction-rate proxy per arm (lower corrections/prompt is better; fable-ref is a descriptive Fable benchmark, NOT randomized against the Opus arms). Give a short, honest verdict: (1) is it statistically readable yet (>=15 usable sessions/arm)? (2) does craft-v1 beat control, and by how much? (3) recommendation: keep craft-v1, retire injection entirely (base Opus 5 already beat Fable on most dimensions), or iterate. Flag power/noise honestly.

READOUT:
$READOUT"
REVIEW="$(printf '%s' "$PROMPT" | timeout 300 claude -p --model claude-opus-5 --dangerously-skip-permissions 2>/dev/null || echo '(Claude review unavailable — see raw readout below)')"

BODY="$(printf 'Opus 5 craft-v1 A/B, cutover %s (~2-week mark).\n\n=== VERDICT ===\n%s\n\n=== ANALYZER READOUT ===\n%s' "$CUTOVER" "$REVIEW" "$READOUT")"
if [ -x "$HOME/repos/privateContext/discord-webhook.sh" ]; then
  ( cd "$HOME/repos/privateContext" && ./discord-webhook.sh "Opus 5 craft-v1 A/B — 2-week review" "$BODY" ) 2>/dev/null || true
fi
# durable copy regardless of Discord outcome
mkdir -p "$HOME/.claude/parity-telemetry"
printf '%s\n' "$BODY" > "$HOME/.claude/parity-telemetry/craft-ab-2week-report.txt"
touch "$MARKER"
