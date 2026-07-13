#!/usr/bin/env bash
# Stop hook (Tier 2: blocks, never invokes Claude): report-evidence audit.
#
# Enforces the fable-parity layer's final-message-evidence rule mechanically:
# a final report that (a) points at "output above / shown earlier" or (b) claims
# a green suite/CI, while containing NO fenced code block that could hold that
# evidence, is bounced back once with a revision instruction.
#
# Empirical basis: every blind-judged loss in the 2026-07-06 fable-opus parity
# matrix traced to exactly this failure mode (in both models). See
# agentGuidance/guidance/opus-fable-parity.md.
#
# Known false-positive class (live-fired 2026-07-06): a reply that QUOTES a
# green-claim while declining to assert it ("you asked me to say 'CI is green'
# but I won't") matches V2 and takes the one-block revision round trip. Cost is
# one extra turn; the revision cycle handled it correctly in the live test.
#
# Deployment: intended for HEADLESS pipeline hosts (VM #requests worker). Not
# for interactive sessions, where mid-conversation references are normal.
# Blocks at most once per session; honors stop_hook_active.
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

# Standard loop prevention: never block a continuation of our own block.
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Block-once-per-session guard.
MARKER="/tmp/claude-report-audit-${SESSION_ID}"
[ -f "$MARKER" ] && exit 0

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -f "$TRANSCRIPT" ] || exit 0

# Final assistant message text (concatenated text blocks of the last assistant entry).
FINAL=$(jq -rs '[.[] | select(.type == "assistant")] | last
                | .message.content // []
                | map(select(.type == "text") | .text) | join("\n")' "$TRANSCRIPT" 2>/dev/null || true)
[ -z "$FINAL" ] && exit 0

# Evidence present? Any fenced code block whose content looks like runner/command
# output (test summaries, prompts, exit codes) counts as pasted evidence.
HAS_EVIDENCE_FENCE=0
if printf '%s' "$FINAL" | awk '/^```/{f=!f; next} f' | grep -qE 'Ran [0-9]+ test|^OK$|OK \(|PASSED|FAILED|passed|exit(ed)? (code )?0|\$ |^> |Tests:' ; then
    HAS_EVIDENCE_FENCE=1
fi
[ "$HAS_EVIDENCE_FENCE" -eq 1 ] && exit 0

VIOLATION=""

# V1: dangling reference to evidence that is not in this message.
if printf '%s' "$FINAL" | grep -qiE '(output|result|transcript|run|logs?) (is |are )?(shown|pasted|included|displayed|printed)? ?(above|earlier)|as (shown|demonstrated|seen) (above|earlier)|see (the )?(output|above)'; then
    VIOLATION="references evidence ('shown above / earlier') that is not present in the final message"
fi

# V2: green claim with no pasted runner output anywhere in the message.
if [ -z "$VIOLATION" ] && printf '%s' "$FINAL" | grep -qiE '(all |the )?tests? (now |all )?pass|test suite (is |now |looks )?(green|passing|clean)|suite (passes|is green)|CI is green|[0-9]+/[0-9]+ (tests? )?(pass|passing|ok)'; then
    VIOLATION="claims a passing suite/CI without pasting the actual runner output"
fi

[ -z "$VIOLATION" ] && exit 0

touch "$MARKER"
REASON="REPORT-EVIDENCE GATE: your final message ${VIOLATION}. The reader sees only this final message — they do not see the session that produced it. Revise the final message so that every claimed piece of evidence is physically present in it: re-run the check if needed and paste the verbatim output inside a fenced code block, or rewrite the claim to match what is actually shown. Do not add new scope; only make the report match the evidence."
jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
exit 0
