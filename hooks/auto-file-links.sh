#!/bin/bash
# auto-file-links.sh — PostToolUse hook for Bash
# Detects git push of any .md files and auto-posts them to Discord #file-links.
#
# Triggered by PostToolUse on Bash commands containing "git push".
# Reads the tool input from stdin (JSON with tool_input.command).

set -uo pipefail

INPUT=$(cat)

# Extract the bash command that was run
CMD=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except:
    print('')
" 2>/dev/null)

# Only act on git push commands
case "$CMD" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

# Extract the repo root from the command (look for cd or use cwd)
REPO_DIR=$(echo "$CMD" | grep -oP '(?<=cd\s)[^\s&;]+' | head -1)
if [ -z "$REPO_DIR" ]; then
  # Try tool_input.cwd or fall back to common locations
  REPO_DIR=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('cwd', ''))
except:
    print('')
" 2>/dev/null)
fi

# Expand ~ and resolve
REPO_DIR="${REPO_DIR/#\~/$HOME}"
[ -z "$REPO_DIR" ] && exit 0
[ -d "$REPO_DIR/.git" ] || [ -f "$REPO_DIR/.git" ] || exit 0

cd "$REPO_DIR" 2>/dev/null || exit 0

# Get the remote URL to build GitHub links
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
[ -z "$REMOTE_URL" ] && exit 0

# Convert SSH/HTTPS remote to GitHub blob base URL
GITHUB_BASE=$(echo "$REMOTE_URL" | sed -E '
  s|git@github\.com:|https://github.com/|
  s|\.git$||
')

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

# Get files changed in the most recent push (last commit vs its parent)
# Use the latest commit since the push just happened
PUSHED_FILES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null)
[ -z "$PUSHED_FILES" ] && exit 0

# Filter for .md files, excluding routine/config docs
ARTIFACTS=$(echo "$PUSHED_FILES" | grep -iE '\.md$' \
  | grep -viE '(README|CHANGELOG|CLAUDE|MEMORY|config|\.claude/|node_modules|package)' \
  || true)

[ -z "$ARTIFACTS" ] && exit 0

# Post each artifact to #file-links
FILE_LINKS_SCRIPT="$HOME/repos/privateContext/file-links-post.sh"
[ -x "$FILE_LINKS_SCRIPT" ] || exit 0

for artifact in $ARTIFACTS; do
  FILENAME=$(basename "$artifact")
  # Build a human-readable description from the filename
  DESC=$(echo "$FILENAME" | sed 's/\.md$//; s/\.txt$//; s/-/ /g; s/_/ /g')
  URL="${GITHUB_BASE}/blob/${BRANCH}/${artifact}"
  "$FILE_LINKS_SCRIPT" "$DESC" "$URL" 2>/dev/null || true
done

exit 0
