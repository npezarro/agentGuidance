#!/bin/bash
# Session Start Hook (agentGuidance project)
# Displays session context (context.md, git status).
# agent.md is loaded by the global fetch-rules.sh hook; no need to fetch it here.

set -euo pipefail

echo "=== Session Start ==="

# 1. Check if local agentGuidance repo is current
REPO_DIR="/home/generatedByTermius/agentGuidance"
if [ -d "$REPO_DIR/.git" ]; then
    BEHIND=$(git -C "$REPO_DIR" rev-list HEAD..origin/main --count 2>/dev/null || echo "?")
    if [ "$BEHIND" = "0" ]; then
        echo "[OK] Fetched latest agent guidance from remote"
    elif [ "$BEHIND" = "?" ]; then
        echo "[OK] Local agent guidance available (remote check skipped)"
    else
        echo "[WARN] Local agentGuidance is ${BEHIND} commit(s) behind origin/main"
    fi
else
    echo "[WARN] agentGuidance repo not found at $REPO_DIR"
fi

# 2. Show context.md if it exists
if [ -f "context.md" ]; then
    echo ""
    echo "=== Project Context ==="
    cat context.md
    echo ""
else
    echo "[INFO] No context.md found; consider creating one from templates/context.md"
fi

# 3. Show current git state
echo ""
echo "=== Git Status ==="
echo "Branch: $(git branch --show-current 2>/dev/null || echo 'not a git repo')"
echo "Last commit: $(git log --oneline -1 2>/dev/null || echo 'no commits')"
echo "Status: $(git status --short 2>/dev/null | wc -l) file(s) changed"

echo ""
echo "=== Ready ==="
