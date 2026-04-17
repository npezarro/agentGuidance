#!/bin/bash
# Install Claude Code rules from agentGuidance/rules/ to ~/.claude/rules/
# Run this on any new machine to bootstrap the rules that Claude Code auto-loads.
# Usage: bash scripts/install-rules.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULES_SRC="$(dirname "$SCRIPT_DIR")/rules"
RULES_DST="$HOME/.claude/rules"

if [ ! -d "$RULES_SRC" ]; then
  echo "Error: Source rules directory not found at $RULES_SRC" >&2
  exit 1
fi

mkdir -p "$RULES_DST"

COPIED=0
for f in "$RULES_SRC"/*.md; do
  [ -f "$f" ] || continue
  BASENAME="$(basename "$f")"
  cp "$f" "$RULES_DST/$BASENAME"
  echo "  Installed $BASENAME"
  COPIED=$((COPIED + 1))
done

echo "Done. $COPIED rule(s) installed to $RULES_DST"
