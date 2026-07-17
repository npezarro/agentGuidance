#!/usr/bin/env bash
# parity-layer-injection.sh -- SessionStart hook.
#
# Injects the validated Opus->Fable parity layer (guidance/opus-fable-parity.md,
# marker block) into INTERACTIVE OPUS sessions only, as a 50/50 A/B.
# (85/15 from 2026-07-10 to 2026-07-16; flipped to 50/50 because control accrued
# ~0.35 sessions/day and the test was unreadable — see the guidance doc's
# "Interactive-session rollout" section. Analyzer: scripts/parity-arm-analyzer.py.)
# The arm is derived deterministically from the session id, so it is stable across
# resume/compact (a control session never flips to treated mid-way). Every
# interactive Opus session's arm is logged so layer-on vs control outcomes can be
# compared going forward.
#
# Emits nothing (exit 0) -- i.e. no layer, and for pipelines no telemetry -- when:
#   - headless (claude -p / --print): protects Haiku/Sonnet local pipelines
#     (security-scanner, autonomousDev, fix-checker, ...) from a misfiring layer
#   - effective model is not Opus (--model override, or non-opus settings default):
#     the layer is validated no-gain on Fable and misfires on Sonnet/Haiku
#   - the process could not be identified (fail closed toward protecting pipelines)
#   - the canonical layer file is missing
#
# Wired into ~/.claude/settings.json SessionStart hooks. Layer source of truth is
# the marker block in guidance/opus-fable-parity.md -- a future v5 auto-propagates.
#
# Process detection uses /proc on Linux/WSL, `ps` on darwin/BSD.
# Testability: set PARITY_CMDLINE_OVERRIDE to bypass process detection entirely.

set -uo pipefail

LAYER_FILE="$HOME/repos/agentGuidance/guidance/opus-fable-parity.md"
TELEMETRY_FILE="${PARITY_TELEMETRY_FILE:-$HOME/.claude/parity-telemetry/interactive-arms.jsonl}"
TELEMETRY_DIR="$(dirname "$TELEMETRY_FILE")"
# version is read from the layer file's PARITY-LAYER-VERSION marker so telemetry
# tracks a future v5 automatically; fallback matches the last known version
LAYER_VERSION="$(grep -oE 'PARITY-LAYER-VERSION: v[0-9]+' "$LAYER_FILE" 2>/dev/null | head -1 | sed 's/.*: //')"
[ -n "$LAYER_VERSION" ] || LAYER_VERSION="v4"
TREAT_PCT=50   # percent of interactive Opus sessions assigned the layer (50/50 since 2026-07-16)

[ -f "$LAYER_FILE" ] || exit 0

# --- read hook stdin (source, session_id) ---
STDIN_JSON="$(cat 2>/dev/null || echo '{}')"
SOURCE="$(printf '%s' "$STDIN_JSON" | jq -r '.source // empty' 2>/dev/null || true)"
SID="$(printf '%s' "$STDIN_JSON" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -z "$SID" ] && SID="${CLAUDE_CODE_SESSION_ID:-}"

# --- identify the claude invocation from the process tree ---
# Linux/WSL expose /proc; darwin/BSD do not, so fall back to `ps`. Both walk up
# to 6 ancestors looking for the claude invocation's argv.
CMDLINE="${PARITY_CMDLINE_OVERRIDE:-}"
if [ -z "$CMDLINE" ]; then
  pid="$PPID"
  for _ in 1 2 3 4 5 6; do
    if [ -r "/proc/$pid/cmdline" ]; then
      c="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
      next="$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null || echo "")"
    elif command -v ps >/dev/null 2>&1; then
      # darwin/BSD: `ps -o ppid=,command=` yields "<ppid> <argv...>"
      line="$(ps -o ppid=,command= -p "$pid" 2>/dev/null || true)"
      [ -n "$line" ] || break
      next="$(printf '%s' "$line" | awk '{print $1}')"
      c="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+//')"
    else
      break
    fi
    if printf '%s' "$c" | grep -qE '(^|/| )claude(\.exe)?( |$)'; then
      CMDLINE="$c"; break
    fi
    pid="$next"
    { [ -z "$pid" ] || [ "$pid" = "0" ] || [ "$pid" = "1" ]; } && break
  done
fi

# the invocation must actually look like a claude process (also validates test overrides)
if [ -n "$CMDLINE" ] && ! printf '%s' " $CMDLINE " | grep -qE '(^| |/)claude(\.exe)?( |$)'; then
  CMDLINE=""
fi
# fail closed: if we cannot identify the invocation, do not risk polluting a pipeline
[ -n "$CMDLINE" ] || exit 0

# --- GUARD 1: headless (-p / --print) -> skip ---
if printf '%s' " $CMDLINE " | grep -qE ' (-p|--print)([ =]|$)'; then
  exit 0
fi

# --- GUARD 2 + ARM: Opus enters the A/B; Fable is logged as the reference cohort ---
# fable-ref sessions NEVER get the layer (validated no-gain on Fable) — they are
# telemetry-only, so interactive Fable usage lands in the same metrics as the two
# Opus arms and serves as the benchmark the layer is chasing. Sonnet/Haiku still
# exit silently (not a relevant cohort; layer misfires there).
MODEL="$(printf '%s' "$CMDLINE" | grep -oE -- '--model[= ][^ ]+' | head -1 | sed -E 's/--model[= ]//' || true)"
[ -z "$MODEL" ] && MODEL="$(jq -r '.model // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)"
case "$MODEL" in
  *[Oo]pus*)
    # deterministic 50/50 from session id (stable across resume/compact)
    if [ -n "$SID" ]; then
      H="$(printf '%s' "$SID" | cksum | cut -d' ' -f1)"
      if [ "$((H % 100))" -lt "$TREAT_PCT" ]; then ARM="layer"; else ARM="control"; fi
    else
      ARM="layer"   # no session id: default to rigor rather than silently dropping it
    fi
    ;;
  *[Ff]able*) ARM="fable-ref" ;;
  *) exit 0 ;;
esac

# --- TELEMETRY: log once per session (startup/resume), not on every compact ---
case "${SOURCE:-startup}" in
  startup|resume)
    mkdir -p "$TELEMETRY_DIR"
    TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"ts":"%s","session_id":"%s","model":"%s","arm":"%s","layer_version":"%s","source":"%s"}\n' \
      "$TS" "$SID" "$MODEL" "$ARM" "$LAYER_VERSION" "${SOURCE:-startup}" >> "$TELEMETRY_FILE"
    ;;
esac

# --- INJECT: treated arm only ---
[ "$ARM" = "layer" ] || exit 0

BLOCK="$(sed -n '/<!-- PARITY-LAYER-START -->/,/<!-- PARITY-LAYER-END -->/p' "$LAYER_FILE" | sed '/<!-- PARITY-LAYER-/d')"
[ -n "$BLOCK" ] || exit 0

printf 'OPERATING PRINCIPLES (Opus->Fable parity layer %s -- interactive session, treated arm):\n%s\n' "$LAYER_VERSION" "$BLOCK"
exit 0
