#!/usr/bin/env bash
# PostToolUse hook for Bash|Edit|Write: records which repo files this session wrote.
#
# TWO ledgers, deliberately separate:
#
#   /tmp/claude-repos-touched-{session_id}   Edit/Write only. PROOF of authorship.
#       Consumed by check-unpushed.sh (Stop gate) and check-commit-deploy.sh.
#       A false entry here blocks a session's exit, so only real tool-level writes
#       are allowed in.
#
#   /tmp/claude-repos-claimed-{session_id}   Bash-inferred probable writes (heredocs,
#       redirects, sed -i, python rewrites). ADVISORY only, consumed by claim-guard.sh.
#       Inference is heuristic, so it never reaches the push gate. This exists because
#       2026-07-30 showed the exact file that nearly got clobbered (browser-agent
#       progress.md, rewritten via a python heredoc) was invisible to the Edit/Write
#       tracker while a second live session was committing the same path.
#
# Both use TAB-separated:  <repo_root>\t<file_path>\t<epoch_seconds>
# The epoch is field 3 so `cut -f1` and two-field readers keep working.
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

LIB="$HOME/repos/agentGuidance/hooks/lib/write-target-inference.sh"
[ -f "$LIB" ] || exit 0
# shellcheck source=lib/write-target-inference.sh
. "$LIB"

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
NOW=$(date +%s)

# log_path <file_path> <ledger_file>
log_path() {
  local repo_root
  repo_root=$(wti_repo_root "$1")
  [ -z "$repo_root" ] && return 0
  printf '%s\t%s\t%s\n' "$repo_root" "$1" "$NOW" >> "$2"
}

if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$CMD" ] && exit 0
  wti_is_write_cmd "$CMD" || exit 0

  PAYLOAD_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  EFF_CWD=$(wti_effective_cwd "$CMD" "$PAYLOAD_CWD")
  [ -n "$EFF_CWD" ] && [ -d "$EFF_CWD" ] || exit 0

  LEDGER="/tmp/claude-repos-claimed-${SESSION_ID}"
  while IFS= read -r cand; do
    [ -n "$cand" ] && log_path "$cand" "$LEDGER"
  done < <(wti_candidate_paths "$CMD" "$EFF_CWD")
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0
log_path "$FILE_PATH" "/tmp/claude-repos-touched-${SESSION_ID}"
exit 0
