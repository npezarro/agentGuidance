#!/bin/bash
# Propagate project-level .claude/settings.json, CLAUDE.md, and .gitattributes to all GitHub repos.
# Uses GitHub API SHA comparison to skip repos that are already current (avoids cloning every repo).
# Requires: gh auth login (or a PAT in GH_TOKEN)
# Usage: bash scripts/propagate-hooks.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE="${REPO_ROOT}/templates/claude-project/settings.json"
CLAUDE_MD="${REPO_ROOT}/CLAUDE.md"
GITATTRIBUTES="${REPO_ROOT}/templates/.gitattributes"
DRY_RUN=false
FORCE=false
WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; echo "[DRY RUN] No changes will be pushed."; shift ;;
    --force)   FORCE=true; echo "[FORCE] Will clone and update all repos regardless of SHA match."; shift ;;
    *)         shift ;;
  esac
done

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

# Compute local file content hashes (git blob SHA format for comparison with GitHub API)
# GitHub API returns git blob SHAs, so we compute the same way
compute_git_sha() {
  local file="$1"
  if [ -f "$file" ]; then
    python3 -c "
import hashlib, sys
data = open(sys.argv[1], 'rb').read()
header = f'blob {len(data)}\0'.encode()
print(hashlib.sha1(header + data).hexdigest())
" "$file"
  else
    echo ""
  fi
}

LOCAL_SETTINGS_SHA=$(compute_git_sha "$TEMPLATE")
LOCAL_CLAUDE_MD_SHA=$(compute_git_sha "$CLAUDE_MD")
LOCAL_GITATTRIBUTES_SHA=$(compute_git_sha "$GITATTRIBUTES")

echo "Local file SHAs:"
echo "  settings.json:  ${LOCAL_SETTINGS_SHA:0:12}..."
echo "  CLAUDE.md:      ${LOCAL_CLAUDE_MD_SHA:0:12}..."
echo "  .gitattributes: ${LOCAL_GITATTRIBUTES_SHA:0:12}..."
echo ""

TOTAL=0
UPDATED=0
SKIPPED=0
CURRENT=0
FAILED=0

for REPO in $REPOS; do
  TOTAL=$((TOTAL + 1))

  if echo "$SKIP_REPOS" | grep -qw "$REPO"; then
    echo "[$TOTAL] SKIP $REPO (in skip list)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # --- SHA comparison via GitHub API (no clone needed) ---
  if ! $FORCE; then
    NEEDS_UPDATE=false

    # Check each file's SHA on the remote
    REMOTE_SETTINGS_SHA=$(gh api "repos/${GH_OWNER}/${REPO}/contents/.claude/settings.json" --jq '.sha' 2>/dev/null || echo "missing")
    REMOTE_CLAUDE_MD_SHA=$(gh api "repos/${GH_OWNER}/${REPO}/contents/CLAUDE.md" --jq '.sha' 2>/dev/null || echo "missing")
    REMOTE_GITATTRIBUTES_SHA=$(gh api "repos/${GH_OWNER}/${REPO}/contents/.gitattributes" --jq '.sha' 2>/dev/null || echo "missing")

    if [ "$REMOTE_SETTINGS_SHA" != "$LOCAL_SETTINGS_SHA" ] || \
       [ "$REMOTE_CLAUDE_MD_SHA" != "$LOCAL_CLAUDE_MD_SHA" ] || \
       [ "$REMOTE_GITATTRIBUTES_SHA" != "$LOCAL_GITATTRIBUTES_SHA" ]; then
      NEEDS_UPDATE=true
    fi

    if ! $NEEDS_UPDATE; then
      echo "[$TOTAL] CURRENT $REPO (all files match)"
      CURRENT=$((CURRENT + 1))
      continue
    fi

    # Show which files differ
    DIFF_FILES=""
    [ "$REMOTE_SETTINGS_SHA" != "$LOCAL_SETTINGS_SHA" ] && DIFF_FILES="${DIFF_FILES} settings.json"
    [ "$REMOTE_CLAUDE_MD_SHA" != "$LOCAL_CLAUDE_MD_SHA" ] && DIFF_FILES="${DIFF_FILES} CLAUDE.md"
    [ "$REMOTE_GITATTRIBUTES_SHA" != "$LOCAL_GITATTRIBUTES_SHA" ] && DIFF_FILES="${DIFF_FILES} .gitattributes"
    echo "[$TOTAL] UPDATING $REPO (differs:${DIFF_FILES})"
  else
    echo "[$TOTAL] Processing ${GH_OWNER}/$REPO (force mode)..."
  fi

  # --- Clone and update (only for repos that need it) ---
  REPO_DIR="${WORKDIR}/${REPO}"

  if ! gh repo clone "${GH_OWNER}/$REPO" "$REPO_DIR" -- --depth 1 2>/dev/null; then
    echo "  FAILED to clone. Skipping."
    FAILED=$((FAILED + 1))
    continue
  fi

  # Create .claude directory if needed
  mkdir -p "${REPO_DIR}/.claude"

  # Copy files
  cp "$TEMPLATE" "${REPO_DIR}/.claude/settings.json"
  [ -f "$CLAUDE_MD" ] && cp "$CLAUDE_MD" "${REPO_DIR}/CLAUDE.md"
  [ -f "$GITATTRIBUTES" ] && cp "$GITATTRIBUTES" "${REPO_DIR}/.gitattributes"

  # Verify there are actual changes (safety check)
  cd "$REPO_DIR"
  if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "  No changes needed (SHA mismatch was false positive)."
    SKIPPED=$((SKIPPED + 1))
    cd "$WORKDIR"
    rm -rf "$REPO_DIR"
    continue
  fi

  if $DRY_RUN; then
    echo "  [DRY RUN] Would commit and push:"
    git status --short
    UPDATED=$((UPDATED + 1))
    cd "$WORKDIR"
    rm -rf "$REPO_DIR"
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
  rm -rf "$REPO_DIR"
done

echo ""
echo "=== Propagation Complete ==="
echo "Total: $TOTAL | Updated: $UPDATED | Already current: $CURRENT | Skipped: $SKIPPED | Failed: $FAILED"
