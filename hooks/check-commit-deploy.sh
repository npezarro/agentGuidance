#!/usr/bin/env bash
# Stop hook: blocks session exit if files were committed to a deployed repo
# but the service was never deployed during this session.
#
# Reads repos-touched tracker (from track-repo-writes.sh), cross-references
# with deploy-registry.json, and checks deploy tracker (from track-deploy.sh).
# Only flags repos where git shows new commits (not just edits).
set -euo pipefail

INPUT=$(cat)
SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0

REGISTRY="$HOME/repos/privateContext/deploy-registry.json"
[ -f "$REGISTRY" ] || exit 0

TOUCHED="/tmp/claude-repos-touched-${SID}"
DEPLOYED="/tmp/claude-deploys-${SID}"

[ -f "$TOUCHED" ] || exit 0

DEPLOYED_SVCS=""
[ -f "$DEPLOYED" ] && DEPLOYED_SVCS=$(cat "$DEPLOYED")
# verify-deploy.sh consumes the live tracker into a -verified file; count those too.
VERIFIED="/tmp/claude-deploys-verified-${SID}"
[ -f "$VERIFIED" ] && DEPLOYED_SVCS="${DEPLOYED_SVCS}
$(cat "$VERIFIED")"
# Docs-only acknowledgment file: services listed here are treated as satisfied.
# Used when new commits touch no runtime files, or when the deploy was performed
# by a subagent (different session_id, so track-deploy.sh never saw it).
ACK="/tmp/claude-deploy-ack-${SID}"
[ -f "$ACK" ] && DEPLOYED_SVCS="${DEPLOYED_SVCS}
$(cat "$ACK")"

MISSING=""

REPO_ROOTS=$(cut -f1 "$TOUCHED" | sort -u)

while IFS= read -r REPO_ROOT; do
  [ -z "$REPO_ROOT" ] && continue
  REPO_NAME=$(basename "$REPO_ROOT")

  SVC=$(jq -r --arg repo "$REPO_NAME" \
    '.services | to_entries[] | select(.value.repo == $repo) | .key' \
    "$REGISTRY" 2>/dev/null || true)
  [ -z "$SVC" ] && continue

  if ! cd "$REPO_ROOT" 2>/dev/null; then
    continue
  fi

  HAS_NEW_COMMITS=$(git log --oneline --since="6 hours ago" -1 2>/dev/null || true)
  [ -z "$HAS_NEW_COMMITS" ] && continue

  # Skip if all recent commits are on non-default branches (e.g. doc-sync PR branches).
  # PR-only commits don't change the deployed artifact, so no service restart is needed.
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
  MAIN_NEW=$(git log --oneline --since="6 hours ago" "$DEFAULT_BRANCH" -1 2>/dev/null || true)
  [ -z "$MAIN_NEW" ] && continue

  if echo "$DEPLOYED_SVCS" | grep -qx "$SVC" 2>/dev/null; then
    continue
  fi

  DEPLOY_CMD=$(jq -r --arg svc "$SVC" '.services[$svc].deployCmd // empty' "$REGISTRY" 2>/dev/null || true)
  HINT=""
  [ -n "$DEPLOY_CMD" ] && HINT=" (deploy with: $DEPLOY_CMD)"

  MISSING="${MISSING}  - ${SVC} (repo: ${REPO_NAME})${HINT}\n"
done <<< "$REPO_ROOTS"

if [ -n "$MISSING" ]; then
  MSG="COMMIT WITHOUT DEPLOY: Files were modified in deployed repos but no deploy was performed:\n${MISSING}Deploy these services before ending the session. ONLY IF the new commits are docs-only (no runtime files) or the deploy already ran inside a subagent (verify the live health endpoint first), acknowledge with: echo '<service>' >> /tmp/claude-deploy-ack-${SID}"
  printf '{"decision":"block","reason":"%s"}' "$(printf "$MSG" | tr '\n' ' ')"
fi

exit 0
