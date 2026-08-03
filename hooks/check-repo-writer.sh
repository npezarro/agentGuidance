#!/usr/bin/env bash
# check-repo-writer.sh — PostToolUse (Edit|Write) hook that warns when a write
# lands in a repo that declares another copy as canonical, or an autonomous
# agent as its writer-of-record.
#
# Repos declare in their CLAUDE.md (anywhere in the file, one per line):
#   writer: <name>            e.g. "writer: learnings-pass" or "writer: human"
#   canonical-copy: <path>    e.g. "canonical-copy: ~/repos/autonomousDev-private"
#
# Semantics:
#   canonical-copy present  -> ANY write here gets a warning (stale mirror).
#   writer: <agent name>    -> interactive writes get a gentle heads-up.
#   writer: human / absent  -> silent.
#
# Motivation: the 2026-06-09 ecosystem review found safety fixes applied to a
# stale public fork instead of the live private tree (split-brain class).

set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -z "$FILE_PATH" ] && exit 0

DIR=$(dirname "$FILE_PATH")
REPO_ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || echo "")
[ -z "$REPO_ROOT" ] && exit 0

CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
[ -f "$CLAUDE_MD" ] || exit 0

CANONICAL=$(grep -m1 -E '^canonical-copy:' "$CLAUDE_MD" 2>/dev/null | sed 's/^canonical-copy:[[:space:]]*//' || true)
WRITER=$(grep -m1 -E '^writer:' "$CLAUDE_MD" 2>/dev/null | sed 's/^writer:[[:space:]]*//' || true)

if [ -n "$CANONICAL" ]; then
  echo "WRITER WARNING: $(basename "$REPO_ROOT") declares its canonical copy at ${CANONICAL}. Edits here do not execute and will drift. Make the change in the canonical copy instead (or update both deliberately)."
  exit 0
fi

if [ -n "$WRITER" ] && [ "$WRITER" != "human" ]; then
  echo "WRITER NOTE: $(basename "$REPO_ROOT") is normally written by '$WRITER'. Interactive edits are allowed but make sure they don't fight the agent's flow (check its state files / open branches before restructuring)."
fi

exit 0
