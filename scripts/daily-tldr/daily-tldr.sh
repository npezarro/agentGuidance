#!/bin/bash
# daily-tldr.sh — Daily repo health check & TLDR report
# Runs at 4AM PT via cron. Iterates repos, collects git activity,
# audits deps, checks builds, posts a Discord summary, and optionally
# creates fix PRs for repos with auto_fix enabled.
#
# Usage: bash scripts/daily-tldr/daily-tldr.sh [--dry-run]
# Requires: node, npm, gh, jq

set -uo pipefail
# Note: -e omitted intentionally — we handle errors per-command with || true
# to avoid SIGPIPE (141) from head/jq truncating pipes

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOS_JSON="${SCRIPT_DIR}/repos.json"
REPORT_DIR="${SCRIPT_DIR}/../../reports"
LOCKFILE="/tmp/daily-tldr.lock"
GLOBAL_TIMEOUT=3600  # 60 min max total runtime
REPO_TIMEOUT=300     # 5 min per repo
DRY_RUN=false
DATE_TAG=$(date +%Y-%m-%d)
REPORT_FILE="${REPORT_DIR}/tldr-${DATE_TAG}.json"

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[DRY RUN] Will collect data but won't post or create PRs."
fi

# --- Lock to prevent concurrent runs ---
exec 200>"$LOCKFILE"
if ! flock -n 200; then
  echo "Another daily-tldr is already running. Exiting."
  exit 1
fi

# --- Ensure report dir exists ---
mkdir -p "$REPORT_DIR"

# --- Load .env if present ---
ENV_FILE="${SCRIPT_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo "Warning: DISCORD_WEBHOOK_URL not set. Report will be saved to file only."
fi

# --- Validate deps ---
for cmd in node npm jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd not found." >&2
    exit 1
  fi
done

REPOS_ROOT=$(jq -r '.repos_root' "$REPOS_JSON")
REPO_NAMES=$(jq -r '.repos | keys[]' "$REPOS_JSON")

# --- Collect data per repo ---
RESULTS="[]"
TOTAL=0
ACTIVE=0
ISSUES=0

for REPO in $REPO_NAMES; do
  TOTAL=$((TOTAL + 1))
  REPO_PATH="${REPOS_ROOT}/${REPO}"

  if [ ! -d "$REPO_PATH/.git" ]; then
    echo "[$REPO] Not a git repo, skipping."
    continue
  fi

  echo "[$REPO] Collecting..."

  SUMMARIZE=$(jq -r ".repos[\"$REPO\"].summarize" "$REPOS_JSON")
  AUDIT_DEPS=$(jq -r ".repos[\"$REPO\"].audit_deps" "$REPOS_JSON")
  CHECK_BUILD=$(jq -r ".repos[\"$REPO\"].check_build" "$REPOS_JSON")
  AUTO_FIX=$(jq -r ".repos[\"$REPO\"].auto_fix" "$REPOS_JSON")

  ENTRY="{}"

  # --- Git activity ---
  if [ "$SUMMARIZE" = "true" ]; then
    COMMIT_COUNT=$(cd "$REPO_PATH" && git log --since="1 day ago" --oneline 2>/dev/null | wc -l)
    COMMITS=""
    if [ "$COMMIT_COUNT" -gt 0 ]; then
      ACTIVE=$((ACTIVE + 1))
      COMMITS=$(cd "$REPO_PATH" && git log --since="1 day ago" --max-count=20 --format="%h %s (%an)" 2>/dev/null)
    fi
    BRANCH=$(cd "$REPO_PATH" && git branch --show-current 2>/dev/null || echo "unknown")
    ENTRY=$(echo "$ENTRY" | jq \
      --arg name "$REPO" \
      --arg branch "$BRANCH" \
      --argjson count "$COMMIT_COUNT" \
      --arg commits "$COMMITS" \
      '. + {name: $name, branch: $branch, commit_count: $count, commits: $commits}')
  fi

  # --- Dep audit ---
  VULN_TOTAL=0
  VULN_HIGH=0
  OUTDATED_COUNT=0
  if [ "$AUDIT_DEPS" = "true" ] && [ -f "${REPO_PATH}/package.json" ]; then
    AUDIT_FILE=$(mktemp)
    OUTDATED_FILE=$(mktemp)
    (cd "$REPO_PATH" && timeout "$REPO_TIMEOUT" npm audit --json > "$AUDIT_FILE" 2>/dev/null) || true
    VULN_TOTAL=$(jq '.metadata.vulnerabilities // {} | to_entries | map(.value) | add // 0' "$AUDIT_FILE" 2>/dev/null || echo "0")
    VULN_HIGH=$(jq '(.metadata.vulnerabilities.high // 0) + (.metadata.vulnerabilities.critical // 0)' "$AUDIT_FILE" 2>/dev/null || echo "0")
    rm -f "$AUDIT_FILE"

    (cd "$REPO_PATH" && timeout "$REPO_TIMEOUT" npm outdated --json > "$OUTDATED_FILE" 2>/dev/null) || true
    OUTDATED_COUNT=$(jq 'length' "$OUTDATED_FILE" 2>/dev/null || echo "0")
    rm -f "$OUTDATED_FILE"

    if [ "$VULN_HIGH" -gt 0 ] 2>/dev/null; then
      ISSUES=$((ISSUES + 1))
    fi

    ENTRY=$(echo "$ENTRY" | jq \
      --argjson vulns "${VULN_TOTAL:-0}" \
      --argjson vuln_high "${VULN_HIGH:-0}" \
      --argjson outdated "${OUTDATED_COUNT:-0}" \
      '. + {vuln_total: $vulns, vuln_high: $vuln_high, outdated_count: $outdated}')
  fi

  # --- Build check ---
  if [ "$CHECK_BUILD" = "true" ] && [ -f "${REPO_PATH}/package.json" ]; then
    HAS_BUILD=$(cd "$REPO_PATH" && node -e "const p=require('./package.json'); process.exit(p.scripts?.build ? 0 : 1)" 2>/dev/null && echo "true" || echo "false")
    if [ "$HAS_BUILD" = "true" ]; then
      BUILD_OK=$(cd "$REPO_PATH" && timeout "$REPO_TIMEOUT" npm run build --silent 2>/dev/null && echo "true" || echo "false")
      if [ "$BUILD_OK" = "false" ]; then
        ISSUES=$((ISSUES + 1))
      fi
      ENTRY=$(echo "$ENTRY" | jq --argjson ok "$([ "$BUILD_OK" = "true" ] && echo true || echo false)" '. + {build_ok: $ok}')
    fi
  fi

  # --- Auto-fix (phase 1: npm audit fix only) ---
  if [ "$AUTO_FIX" = "true" ] && [ "$DRY_RUN" = "false" ]; then
    FIX_BRANCH="claude/daily-tldr-${DATE_TAG}"
    FIX_APPLIED=false

    # Only attempt if there are fixable vulns
    if [ "${VULN_TOTAL:-0}" -gt 0 ]; then
      cd "$REPO_PATH"
      CURRENT_BRANCH=$(git branch --show-current)
      git stash --quiet 2>/dev/null || true
      git checkout -b "$FIX_BRANCH" 2>/dev/null || git checkout "$FIX_BRANCH" 2>/dev/null || true

      timeout "$REPO_TIMEOUT" npm audit fix --force 2>/dev/null || true

      if ! git diff --quiet 2>/dev/null; then
        git add -A
        git commit -m "chore: daily auto-fix — npm audit fix (${DATE_TAG})" 2>/dev/null || true
        if git push origin "$FIX_BRANCH" 2>/dev/null; then
          # Create PR via gh
          if command -v gh &>/dev/null; then
            gh pr create \
              --title "chore: daily auto-fix (${DATE_TAG})" \
              --body "Automated npm audit fix from daily-tldr job.

Generated at $(date -Iseconds)" \
              --base main \
              --head "$FIX_BRANCH" 2>/dev/null || true
          fi
          FIX_APPLIED=true
        fi
      fi

      git checkout "$CURRENT_BRANCH" 2>/dev/null || true
      git stash pop --quiet 2>/dev/null || true
      cd "$SCRIPT_DIR"
    fi

    ENTRY=$(echo "$ENTRY" | jq --argjson fixed "$FIX_APPLIED" '. + {auto_fix_applied: $fixed}')
  fi

  RESULTS=$(echo "$RESULTS" | jq --argjson entry "$ENTRY" '. + [$entry]')
done

# --- Write JSON report ---
REPORT=$(jq -n \
  --arg date "$DATE_TAG" \
  --arg generated "$(date -Iseconds)" \
  --argjson total "$TOTAL" \
  --argjson active "$ACTIVE" \
  --argjson issues "$ISSUES" \
  --argjson repos "$RESULTS" \
  '{date: $date, generated: $generated, total_repos: $total, active_repos: $active, issues_found: $issues, repos: $repos}')

echo "$REPORT" > "$REPORT_FILE"
echo "Report saved to $REPORT_FILE"

# --- Post to Discord ---
if [ -n "${DISCORD_WEBHOOK_URL:-}" ] && [ "$DRY_RUN" = "false" ]; then
  node "${SCRIPT_DIR}/format-report.js" "$REPORT_FILE"
  echo "Discord report posted."
elif [ "$DRY_RUN" = "true" ]; then
  echo "[DRY RUN] Would post to Discord. Report preview:"
  echo "$REPORT" | jq '.repos[] | {name, commit_count, vuln_total, build_ok}'
fi

echo "Daily TLDR complete. Repos: $TOTAL | Active: $ACTIVE | Issues: $ISSUES"
