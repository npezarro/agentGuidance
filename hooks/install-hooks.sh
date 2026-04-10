#!/usr/bin/env bash
# Install pre-commit and pre-push security hooks to repos.
#
# Usage:
#   bash install-hooks.sh                    # Install to current repo
#   bash install-hooks.sh --all-public       # Install to all local public repos
#   bash install-hooks.sh /path/to/repo      # Install to specific repo
#
# Hooks call security-scan.sh from privateContext to detect sensitive
# identifiers before they reach a public remote.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRE_COMMIT="$SCRIPT_DIR/git-pre-commit"
PRE_PUSH="$SCRIPT_DIR/git-pre-push"

install_hooks() {
  local repo_path="$1"
  local hooks_dir="$repo_path/.git/hooks"

  if [ ! -d "$repo_path/.git" ]; then
    echo "  SKIP: $repo_path (not a git repo)"
    return
  fi

  mkdir -p "$hooks_dir"

  # Install pre-commit
  if [ -f "$PRE_COMMIT" ]; then
    cp "$PRE_COMMIT" "$hooks_dir/pre-commit"
    chmod +x "$hooks_dir/pre-commit"
  fi

  # Install pre-push
  if [ -f "$PRE_PUSH" ]; then
    cp "$PRE_PUSH" "$hooks_dir/pre-push"
    chmod +x "$hooks_dir/pre-push"
  fi

  echo "  OK: $repo_path"
}

install_global_template() {
  local template_dir="$HOME/.git-templates/hooks"
  mkdir -p "$template_dir"

  if [ -f "$PRE_COMMIT" ]; then
    cp "$PRE_COMMIT" "$template_dir/pre-commit"
    chmod +x "$template_dir/pre-commit"
  fi

  if [ -f "$PRE_PUSH" ]; then
    cp "$PRE_PUSH" "$template_dir/pre-push"
    chmod +x "$template_dir/pre-push"
  fi

  # Set global git template directory
  git config --global init.templateDir "$HOME/.git-templates"
  echo "  OK: Global template installed at $template_dir"
  echo "  New clones will auto-install hooks."
}

if [ "${1:-}" = "--all-public" ]; then
  echo "Installing hooks to all local public repos..."
  echo ""

  # Get list of public repos
  PUBLIC_REPOS=$(gh repo list npezarro --public --json name -q '.[].name' 2>/dev/null || echo "")

  if [ -z "$PUBLIC_REPOS" ]; then
    echo "ERROR: Could not fetch public repo list (gh CLI issue?)"
    exit 1
  fi

  while IFS= read -r repo_name; do
    repo_path="$HOME/repos/$repo_name"
    if [ -d "$repo_path" ]; then
      install_hooks "$repo_path"
    else
      echo "  SKIP: $repo_name (not cloned locally)"
    fi
  done <<< "$PUBLIC_REPOS"

  echo ""
  echo "Installing global git template..."
  install_global_template

  echo ""
  echo "Done. All public repos protected."

elif [ -n "${1:-}" ]; then
  echo "Installing hooks to $1..."
  install_hooks "$1"

else
  # Default: install to repo containing this script (agentGuidance)
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  echo "Installing hooks to $REPO_ROOT..."
  install_hooks "$REPO_ROOT"
fi
