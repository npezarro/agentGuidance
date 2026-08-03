#!/usr/bin/env bash
# load-repo-context.sh — SessionStart hook: load context for the repo you're
# actually standing in (review proposal 7.4, tiered context).
#
# Tier 0 (global) is the existing always-loaded set. This hook adds Tier 1:
# when the session starts inside a repo, inject that repo's curated context
# pack, its context.md freshness header, and its knowledgeBase page — the
# things a session would otherwise have to remember to go read.
#
# Repos can curate `.claude/context-pack.md` for exact control; otherwise
# we fall back to context.md head + KB page head.

set -euo pipefail

REPO_ROOT=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "")
[ -z "$REPO_ROOT" ] && exit 0
REPO=$(basename "$REPO_ROOT")

# Don't fire for the home-directory pseudo-repo
[ "$REPO_ROOT" = "$HOME" ] && exit 0

OUT=""

PACK="$REPO_ROOT/.claude/context-pack.md"
if [ -f "$PACK" ]; then
  OUT="$(head -c 4000 "$PACK")"
else
  if [ -f "$REPO_ROOT/context.md" ]; then
    OUT="--- $REPO/context.md (head) ---
$(head -20 "$REPO_ROOT/context.md")"
  fi
  KB_PAGE=$(ls "$HOME/repos/knowledgeBase"/*/"$REPO".md 2>/dev/null | head -1 || true)
  if [ -n "$KB_PAGE" ]; then
    OUT="$OUT

--- knowledgeBase: ${KB_PAGE#"$HOME"/repos/} (head) ---
$(head -30 "$KB_PAGE")"
  fi
fi

[ -z "$(echo "$OUT" | tr -d '[:space:]')" ] && exit 0
echo "REPO CONTEXT PACK ($REPO):"
echo "$OUT" | head -c 5000
exit 0
