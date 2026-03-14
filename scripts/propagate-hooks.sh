#!/bin/bash
# Propagate project-level .claude/settings.json to all GitHub repos.
# Requires: gh auth login (or a PAT in GH_TOKEN)
# Usage: bash scripts/propagate-hooks.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE="${REPO_ROOT}/templates/claude-project/settings.json"
CLAUDE_MD="${REPO_ROOT}/CLAUDE.md"
GITATTRIBUTES="${REPO_ROOT}/templates/.gitattributes"
DRY_RUN=false
WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[DRY RUN] No changes will be pushed."
fi

if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI not found. Install it first." >&2
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "Error: gh not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

# Get all repos for the authenticated user
GH_OWNER=$(gh api user --jq '.login' 2>/dev/null || echo "")
if [ -z "$GH_OWNER" ]; then
  echo "Error: Could not determine GitHub username." >&2
  exit 1
fi
REPOS=$(gh repo list "$GH_OWNER" --limit 100 --json name --jq '.[].name')
SKIP_REPOS="agentGuidance"  # Don't self-propagate

TOTAL=0
UPDATED=0
SKIPPED=0
FAILED=0

for REPO in $REPOS; do
  TOTAL=$((TOTAL + 1))

  if echo "$SKIP_REPOS" | grep -qw "$REPO"; then
    echo "[$TOTAL] SKIP $REPO (in skip list)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "[$TOTAL] Processing ${GH_OWNER}/$REPO..."
  REPO_DIR="${WORKDIR}/${REPO}"

  if ! gh repo clone "${GH_OWNER}/$REPO" "$REPO_DIR" -- --depth 1 2>/dev/null; then
    echo "  FAILED to clone. Skipping."
    FAILED=$((FAILED + 1))
    continue
  fi

  # Create .claude directory if needed
  mkdir -p "${REPO_DIR}/.claude"

  # Copy project-level settings.json
  cp "$TEMPLATE" "${REPO_DIR}/.claude/settings.json"

  # Copy CLAUDE.md if it doesn't exist or differs
  if [ -f "$CLAUDE_MD" ]; then
    cp "$CLAUDE_MD" "${REPO_DIR}/CLAUDE.md"
  fi

  # Copy .gitattributes (merge=union for progress.md)
  if [ -f "$GITATTRIBUTES" ]; then
    cp "$GITATTRIBUTES" "${REPO_DIR}/.gitattributes"
  fi

  # Check if there are actual changes
  cd "$REPO_DIR"
  if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "  No changes needed."
    SKIPPED=$((SKIPPED + 1))
    cd "$WORKDIR"
    continue
  fi

  if $DRY_RUN; then
    echo "  [DRY RUN] Would commit and push:"
    git status --short
    UPDATED=$((UPDATED + 1))
    cd "$WORKDIR"
    continue
  fi

  # Commit and push
  BRANCH="chore/propagate-hooks-$(date +%Y%m%d)"
  git checkout -b "$BRANCH" 2>/dev/null
  git add .claude/settings.json CLAUDE.md .gitattributes 2>/dev/null
  git commit -m "chore: propagate Claude Code hooks, CLAUDE.md, and .gitattributes from agentGuidance" 2>/dev/null || true
  if git push origin "$BRANCH" 2>/dev/null; then
    echo "  Pushed successfully."
    UPDATED=$((UPDATED + 1))
  else
    echo "  FAILED to push."
    FAILED=$((FAILED + 1))
  fi

  cd "$WORKDIR"
done

echo ""
echo "=== Propagation Complete ==="
echo "Total: $TOTAL | Updated: $UPDATED | Skipped: $SKIPPED | Failed: $FAILED"
