#!/bin/bash
# Fetch global agent rules from GitHub at session start
# Output is injected into Claude's conversation context

RULES=$(curl -s --max-time 10 https://raw.githubusercontent.com/npezarro/agentGuidance/main/agent.md 2>/dev/null)

if [ -z "$RULES" ]; then
  echo "Warning: Could not fetch global rules from agentGuidance repo" >&2
  exit 0
fi

echo "$RULES"
exit 0
