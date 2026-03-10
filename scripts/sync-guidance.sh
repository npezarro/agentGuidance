#!/bin/bash
# Sync local agentGuidance clone with remote origin.
# Intended to run via cron every 15 minutes.
#
# Install:
#   chmod +x /home/generatedByTermius/agentGuidance/scripts/sync-guidance.sh
#   crontab -e
#   */15 * * * * /home/generatedByTermius/agentGuidance/scripts/sync-guidance.sh >> /var/log/agentguidance-sync.log 2>&1
#
# Uses --ff-only to prevent silent merges if the local branch has diverged.
# Logs success/failure with timestamps for auditability.

set -euo pipefail

REPO_DIR="/home/generatedByTermius/agentGuidance"
LOG_PREFIX="[agentGuidance-sync $(date -Iseconds)]"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "$LOG_PREFIX ERROR: $REPO_DIR is not a git repository"
  exit 1
fi

cd "$REPO_DIR"

# Fetch latest refs
if ! git fetch origin --quiet 2>/dev/null; then
  echo "$LOG_PREFIX WARN: git fetch failed (network issue?)"
  exit 0
fi

# Check if main is behind
LOCAL_SHA=$(git rev-parse main 2>/dev/null || echo "none")
REMOTE_SHA=$(git rev-parse origin/main 2>/dev/null || echo "none")

if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
  # Already up to date — silent success (don't spam logs)
  exit 0
fi

# Attempt fast-forward merge on main
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
if [ "$CURRENT_BRANCH" = "main" ]; then
  if git pull --ff-only --quiet 2>/dev/null; then
    NEW_SHA=$(git rev-parse --short HEAD)
    echo "$LOG_PREFIX OK: Updated main to $NEW_SHA"
  else
    echo "$LOG_PREFIX WARN: Fast-forward failed — local main has diverged. Manual intervention needed."
    exit 1
  fi
else
  # Not on main — update the main ref without switching branches
  if git fetch origin main:main 2>/dev/null; then
    NEW_SHA=$(git rev-parse --short main)
    echo "$LOG_PREFIX OK: Updated main ref to $NEW_SHA (currently on branch: $CURRENT_BRANCH)"
  else
    echo "$LOG_PREFIX WARN: Could not update main ref — may have diverged"
    exit 1
  fi
fi
