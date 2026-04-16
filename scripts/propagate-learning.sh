#!/usr/bin/env bash
# propagate-learning.sh — Single-command multi-destination learning capture
# Replaces manual 4-destination writes with one script call.
#
# Usage:
#   propagate-learning.sh --type <feedback|pattern|infra|rule> \
#     --summary "One-line description" \
#     --body "Full learning content" \
#     [--repo <repo-name>]         # Target repo for CLAUDE.md update
#     [--guidance-file <file.md>]  # Specific guidance file to update (appends)
#     [--cross-cutting]            # Also update knowledgeBase wiki
#     [--memory-name <name>]       # Memory file name (auto-derived if omitted)
#     [--private]                  # Route to privateContext instead of agentGuidance
#     [--dry-run]                  # Show what would happen without writing

set -euo pipefail

REPOS_ROOT="$HOME/repos"
AGENT_GUIDANCE="$REPOS_ROOT/agentGuidance"
PRIVATE_CONTEXT="$REPOS_ROOT/privateContext"
KNOWLEDGE_BASE="$REPOS_ROOT/knowledgeBase"
MEMORY_BASE="$HOME/.claude/projects"

# ── Parse arguments ──────────────────────────────────────────────────
TYPE="" SUMMARY="" BODY="" REPO="" GUIDANCE_FILE="" CROSS_CUTTING=false
MEMORY_NAME="" PRIVATE=false DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)        TYPE="$2"; shift 2 ;;
    --summary)     SUMMARY="$2"; shift 2 ;;
    --body)        BODY="$2"; shift 2 ;;
    --repo)        REPO="$2"; shift 2 ;;
    --guidance-file) GUIDANCE_FILE="$2"; shift 2 ;;
    --cross-cutting) CROSS_CUTTING=true; shift ;;
    --memory-name) MEMORY_NAME="$2"; shift 2 ;;
    --private)     PRIVATE=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$SUMMARY" ] || [ -z "$BODY" ]; then
  echo "Error: --summary and --body are required" >&2
  echo "Usage: propagate-learning.sh --type feedback --summary '...' --body '...'" >&2
  exit 1
fi

TYPE="${TYPE:-pattern}"
SLUG=$(echo "$SUMMARY" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-50)
DATE=$(date +%Y-%m-%d)
DESTINATIONS=()

log() { echo "  [propagate] $1"; }
dry() { if $DRY_RUN; then echo "  [dry-run] $1"; else log "$1"; fi; }

# ── Destination 1: Memory ────────────────────────────────────────────
# Find the primary memory directory (prefer -mnt-c-Users- path, fallback to first available)
PRIMARY_MEMORY=""
for d in "$MEMORY_BASE"/-mnt-c-Users-*/memory "$MEMORY_BASE"/-home-npezarro/memory; do
  if [ -d "$d" ]; then PRIMARY_MEMORY="$d"; break; fi
done

if [ -n "$PRIMARY_MEMORY" ]; then
  MEM_FILE="${MEMORY_NAME:-${TYPE}_${SLUG}}.md"
  MEM_PATH="$PRIMARY_MEMORY/$MEM_FILE"
  if ! $DRY_RUN; then
    cat > "$MEM_PATH" << MEMEOF
---
name: $SUMMARY
description: $SUMMARY
type: ${TYPE}
---

$BODY
MEMEOF
    # Add to MEMORY.md index if not already present
    MEMORY_INDEX="$PRIMARY_MEMORY/MEMORY.md"
    if [ -f "$MEMORY_INDEX" ] && ! grep -q "$MEM_FILE" "$MEMORY_INDEX" 2>/dev/null; then
      echo "- [${MEM_FILE}](${MEM_FILE}) — ${SUMMARY}" >> "$MEMORY_INDEX"
    fi
    DESTINATIONS+=("memory:$MEM_PATH")
  fi
  dry "Memory: $MEM_PATH"
fi

# ── Destination 2: Repo CLAUDE.md ────────────────────────────────────
if [ -n "$REPO" ]; then
  REPO_DIR="$REPOS_ROOT/$REPO"
  CLAUDE_MD="$REPO_DIR/CLAUDE.md"
  if [ -f "$CLAUDE_MD" ]; then
    if ! $DRY_RUN; then
      # Append as a new section if not already present
      if ! grep -qF "$SUMMARY" "$CLAUDE_MD" 2>/dev/null; then
        printf "\n## %s\n%s\n" "$SUMMARY" "$BODY" >> "$CLAUDE_MD"
        (cd "$REPO_DIR" && git add CLAUDE.md && git commit -m "docs: $SUMMARY" && git push -u origin HEAD) 2>/dev/null || true
      fi
    fi
    DESTINATIONS+=("CLAUDE.md:$CLAUDE_MD")
    dry "Repo CLAUDE.md: $CLAUDE_MD"
  else
    dry "SKIP repo CLAUDE.md (not found: $CLAUDE_MD)"
  fi
fi

# ── Destination 3: agentGuidance or privateContext ───────────────────
TARGET_REPO="$AGENT_GUIDANCE"
if $PRIVATE; then TARGET_REPO="$PRIVATE_CONTEXT"; fi

if [ -n "$GUIDANCE_FILE" ]; then
  GUIDANCE_PATH="$TARGET_REPO/$GUIDANCE_FILE"
  if [ -f "$GUIDANCE_PATH" ]; then
    if ! $DRY_RUN; then
      if ! grep -qF "$SUMMARY" "$GUIDANCE_PATH" 2>/dev/null; then
        printf "\n### %s (%s)\n%s\n" "$SUMMARY" "$DATE" "$BODY" >> "$GUIDANCE_PATH"
        (cd "$TARGET_REPO" && git add "$GUIDANCE_FILE" && git commit -m "guidance: $SUMMARY" && git push -u origin HEAD) 2>/dev/null || true
      fi
    fi
    DESTINATIONS+=("guidance:$GUIDANCE_PATH")
    dry "Guidance file: $GUIDANCE_PATH"
  else
    dry "SKIP guidance file (not found: $GUIDANCE_PATH)"
  fi
else
  dry "SKIP guidance (no --guidance-file specified)"
fi

# ── Destination 4: knowledgeBase (cross-cutting only) ────────────────
if $CROSS_CUTTING && [ -d "$KNOWLEDGE_BASE" ]; then
  dry "knowledgeBase: flagged for cross-cutting update (manual wiki edit recommended)"
  DESTINATIONS+=("knowledgeBase:flagged")
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "Learning propagated to ${#DESTINATIONS[@]} destination(s):"
for d in "${DESTINATIONS[@]}"; do echo "  - $d"; done

if $DRY_RUN; then
  echo ""
  echo "(dry run — no files were modified)"
fi
