#!/bin/bash
# Session Start Hook
# Fetches latest agent guidance and displays session context.
# This runs automatically when a Claude Code session starts.

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/npezarro/agentGuidance/main"
GUIDANCE_FILE="agent.md"
LOCAL_GUIDANCE="agent.md"

echo "=== Session Start ==="

# 1. Fetch latest guidance (with timeout, fail silently)
if curl -sf --max-time 5 "${REPO_URL}/${GUIDANCE_FILE}" -o /tmp/agent-guidance-latest.md 2>/dev/null; then
    echo "[OK] Fetched latest agent guidance from remote"
else
    echo "[WARN] Could not fetch remote guidance — using local copy"
fi

# 2. Show context.md summary if it exists
if [ -f "context.md" ]; then
    echo ""
    echo "=== Project Context ==="
    head -20 context.md
    echo ""
else
    echo "[INFO] No context.md found — consider creating one from templates/context.md"
fi

# 3. Show current git state
echo ""
echo "=== Git Status ==="
echo "Branch: $(git branch --show-current 2>/dev/null || echo 'not a git repo')"
echo "Last commit: $(git log --oneline -1 2>/dev/null || echo 'no commits')"
echo "Status: $(git status --short 2>/dev/null | wc -l) file(s) changed"

echo ""
echo "=== Ready ==="
