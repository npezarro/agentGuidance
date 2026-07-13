#!/usr/bin/env bash
# parity-layer-injection.selftest.sh -- reproducible guard/arm matrix for the
# parity SessionStart hook. Codifies the checks run at install (2026-07-10) so the
# hook can be re-validated in one command after any edit.
#
# NOTE on live end-to-end proof: the hook emits its layer text on stdout as
# SessionStart additionalContext -- the SAME mechanism the 8 sibling SessionStart
# hooks use (agent.md, ESSENTIAL, KB, etc.), which demonstrably reach the model's
# context every session. The definitive live proof is that the telemetry sink gets
# its first line on the next interactive Opus session start; this harness proves the
# script's decision logic against the real process tree without needing a TTY.
set -uo pipefail

H="$(cd "$(dirname "$0")" && pwd)/parity-layer-injection.sh"
T="$(mktemp)"; export PARITY_TELEMETRY_FILE="$T"
pass=0; fail=0
chk() { # desc, expected(inject|skip), actual_output
  local desc="$1" exp="$2" out="$3" got="skip"
  [ -n "$out" ] && got="inject"
  if [ "$got" = "$exp" ]; then echo "  PASS  $desc ($got)"; pass=$((pass+1))
  else echo "  FAIL  $desc: expected $exp, got $got"; fail=$((fail+1)); fi
}

# treated sid (sess-A -> layer) and control sid (xyz123 -> control) are deterministic
echo "arm check: sess-A=$(printf sess-A|cksum|cut -d' ' -f1 | awk '{print ($1%100<85)?"layer":"control"}') xyz123=$(printf xyz123|cksum|cut -d' ' -f1 | awk '{print ($1%100<85)?"layer":"control"}')"

chk "interactive opus, treated arm" inject \
  "$(printf '{"source":"startup","session_id":"sess-A"}' | "$H")"
chk "interactive opus, control arm" skip \
  "$(printf '{"source":"startup","session_id":"xyz123"}' | "$H")"
chk "headless -p (protect pipelines)" skip \
  "$(printf '{"source":"startup","session_id":"sess-A"}' | PARITY_CMDLINE_OVERRIDE='claude -p --model haiku' "$H")"
chk "non-opus --model sonnet" skip \
  "$(printf '{"source":"startup","session_id":"sess-A"}' | PARITY_CMDLINE_OVERRIDE='claude --model sonnet' "$H")"
chk "explicit --model opus, treated" inject \
  "$(printf '{"source":"startup","session_id":"sess-A"}' | PARITY_CMDLINE_OVERRIDE='claude --model opus-4-8' "$H")"
chk "unidentified process fails closed" skip \
  "$(printf '{"source":"startup","session_id":"sess-A"}' | PARITY_CMDLINE_OVERRIDE='some-other-proc' "$H")"

# compaction re-injects for treated arm without a new telemetry line
before=$(wc -l < "$T"); out=$(printf '{"source":"compact","session_id":"sess-A"}' | "$H"); after=$(wc -l < "$T")
chk "compact re-injects (treated)" inject "$out"
[ "$before" = "$after" ] && { echo "  PASS  compact adds no telemetry line"; pass=$((pass+1)); } \
                         || { echo "  FAIL  compact added a telemetry line"; fail=$((fail+1)); }

rm -f "$T"
echo "----"; echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
