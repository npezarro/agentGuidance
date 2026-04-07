#!/usr/bin/env bash
# install-hooks.sh — Install git hooks from the tracked hooks/ directory
# Run after cloning: bash scripts/install-hooks.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_SRC="$REPO_ROOT/hooks"
HOOKS_DST="$REPO_ROOT/.git/hooks"

install_hook() {
  local src="$1" dst_name="$2"
  if [ -f "$src" ]; then
    cp "$src" "$HOOKS_DST/$dst_name"
    chmod +x "$HOOKS_DST/$dst_name"
    echo "Installed: $dst_name"
  fi
}

install_hook "$HOOKS_SRC/git-pre-commit" "pre-commit"

echo "Done. Git hooks installed."
