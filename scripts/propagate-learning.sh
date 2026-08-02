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
MEMORY_NAME="" PRIVATE=false DRY_RUN=false NO_OP_OK=false

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
    --no-op-ok)    NO_OP_OK=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$SUMMARY" ] || [ -z "$BODY" ]; then
  if [ "$NO_OP_OK" = true ]; then
    # Caller signals zero new patterns this session — satisfies mandatory Rule 1 trigger idempotently
    exit 0
  fi
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
# Prefer the memory dir belonging to the CURRENT project. Claude derives that
# directory name from the cwd with '/' replaced by '-', so $HOME/repos maps to
# -home-npezarro-repos. Writing to a different project's dir makes the memory
# invisible to the session that just learned the thing (was silently happening
# for every WSL ~/repos session, which landed in the Windows -mnt-c-Users- dir).
#
# $PWD is the wrong signal on its own: this script is usually invoked from a repo
# the session merely operates on (e.g. cd ~/repos/agentGuidance to commit
# guidance), NOT from the session's own project dir. Keying off cwd alone filed
# memories under -home-npezarro-repos-agentGuidance / -home-npezarro-repos, where
# the calling session never reads them and no MEMORY.md exists to index them
# (observed 3x on 2026-07-30). Resolve the CALLING SESSION's project first by
# locating the dir that holds its transcript, then fall back to the cwd guess.
PRIMARY_MEMORY=""
SESSION_PROJECT_DIR=""
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  for p in "$MEMORY_BASE"/*/; do
    if [ -f "${p}${CLAUDE_CODE_SESSION_ID}.jsonl" ]; then
      SESSION_PROJECT_DIR="${p}memory"; break
    fi
  done
fi
CWD_PROJECT_DIR="$MEMORY_BASE/$(echo "$PWD" | sed 's|/|-|g')/memory"
for d in "$SESSION_PROJECT_DIR" "$CWD_PROJECT_DIR" \
         "$MEMORY_BASE"/-home-npezarro-repos/memory \
         "$MEMORY_BASE"/-mnt-c-Users-*/memory "$MEMORY_BASE"/-home-npezarro/memory; do
  [ -n "$d" ] || continue
  if [ -d "$d" ]; then PRIMARY_MEMORY="$d"; break; fi
done

if [ -n "$PRIMARY_MEMORY" ]; then
  MEM_FILE="${MEMORY_NAME:-${TYPE}_${SLUG}}.md"
  MEM_PATH="$PRIMARY_MEMORY/$MEM_FILE"
  if ! $DRY_RUN; then
    # Frontmatter MUST match the documented memory schema: `name` is the
    # kebab/snake slug (NOT the prose summary), and `type` lives under
    # `metadata` with one of user|feedback|project|reference. Emitting a
    # top-level free-form `type:` produced non-conforming files that had to be
    # hand-fixed after every run (2026-07-30).
    case "$TYPE" in
      feedback) MEM_TYPE="feedback" ;;
      project)  MEM_TYPE="project" ;;
      user)     MEM_TYPE="user" ;;
      *)        MEM_TYPE="reference" ;;   # pattern | infra | rule | anything else
    esac
    # NEVER clobber an existing memory. `--memory-name` pointing at a file that
    # already exists means the caller wants to UPDATE it, and a blind `cat >`
    # destroys everything already in there (2026-08-02: wiped the piotr-MCP
    # context, the canonical Drive folder id, and the markdown-conversion quirks
    # out of infra_gdoc_push_headless_fallback.md; also seen in a prior closeout).
    # Write the proposal alongside instead and make the caller merge it.
    MEM_CLOBBER_AVOIDED=false
    if [ -f "$MEM_PATH" ]; then
      MEM_WRITE_PATH="$MEM_PATH.proposed"
      MEM_CLOBBER_AVOIDED=true
    else
      MEM_WRITE_PATH="$MEM_PATH"
    fi
    cat > "$MEM_WRITE_PATH" << MEMEOF
---
name: ${MEM_FILE%.md}
description: $SUMMARY
metadata:
  type: ${MEM_TYPE}
---

$BODY
MEMEOF
    if $MEM_CLOBBER_AVOIDED; then
      echo "  [propagate] ⚠ MEMORY EXISTS, NOT OVERWRITTEN: $MEM_PATH" >&2
      echo "  [propagate] ⚠ proposal written to: $MEM_WRITE_PATH" >&2
      echo "  [propagate] ⚠ MERGE IT BY HAND (keep the existing content), then delete the .proposed file." >&2
    fi
    # Add to MEMORY.md index if not already present.
    # Cap the hook so the always-loaded index stays under its context budget —
    # the full detail lives in the memory file, not the one-line index entry.
    # A companion SessionStart hook (compact-memory-index.sh) re-compacts and
    # warns if the index ever exceeds its hard limit.
    MEMORY_INDEX="$PRIMARY_MEMORY/MEMORY.md"
    if [ -f "$MEMORY_INDEX" ] && ! grep -q "$MEM_FILE" "$MEMORY_INDEX" 2>/dev/null; then
      HOOK_MAX=$(( 128 - ${#MEM_FILE} - ${#MEM_FILE} - 8 ))   # 8 = len("- [](\) — ")
      [ "$HOOK_MAX" -lt 24 ] && HOOK_MAX=24
      HOOK="$SUMMARY"
      if [ "${#HOOK}" -gt "$HOOK_MAX" ]; then
        HOOK="$(printf '%s' "$SUMMARY" | cut -c1-"$HOOK_MAX" | sed 's/[[:space:],;:.—-]*$//')…"
      fi
      # flock is not universal (absent on some Macs/minimal boxes): fall back
      # to an mkdir lock with the same wait-up-to-5s-then-proceed semantics.
      # compact-memory-index.sh takes the same locks around its rewrite.
      if command -v flock >/dev/null 2>&1; then
        ( flock -w 5 9 2>/dev/null || true
          echo "- [${MEM_FILE}](${MEM_FILE}) — ${HOOK}" >> "$MEMORY_INDEX"
        ) 9>"$MEMORY_INDEX.lock" 2>/dev/null
      else
        LOCK_D="$MEMORY_INDEX.lock.d" LOCK_HELD=false WAITED=0
        while :; do
          if mkdir "$LOCK_D" 2>/dev/null; then LOCK_HELD=true; break; fi
          [ "$WAITED" -ge 5 ] && break   # timed out: proceed anyway (matches flock -w 5 || true)
          sleep 1; WAITED=$((WAITED + 1))
        done
        echo "- [${MEM_FILE}](${MEM_FILE}) — ${HOOK}" >> "$MEMORY_INDEX"
        [ "$LOCK_HELD" = true ] && rmdir "$LOCK_D" 2>/dev/null || true
      fi
    fi
    if $MEM_CLOBBER_AVOIDED; then
      DESTINATIONS+=("memory:$MEM_WRITE_PATH (NEEDS MANUAL MERGE into $MEM_PATH)")
    else
      DESTINATIONS+=("memory:$MEM_PATH")
    fi
  fi
  dry "Memory: ${MEM_WRITE_PATH:-$MEM_PATH}"
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
        # --only: commit CLAUDE.md alone, ignoring anything else already staged.
        # A bare `git commit` here commits the whole index, and these repos are
        # shared checkouts — a concurrent session with staged work gets its
        # in-progress changes swept into a "docs:" commit and pushed. Observed
        # 2026-07-30: this published another session's extension/background.js
        # and manifest.json under a docs commit message.
        (cd "$REPO_DIR" && git add CLAUDE.md && git commit --only CLAUDE.md -m "docs: $SUMMARY" && git push -u origin HEAD) 2>/dev/null || true
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
  # Guidance docs live in guidance/, but callers naturally pass the bare filename
  # (--guidance-file git-workflow.md). Resolving only against the repo root made
  # every such call silently SKIP, so the rule this script exists to enforce
  # ("guidance updates go to repo files, not just memory") was quietly no-oping.
  GUIDANCE_REL="$GUIDANCE_FILE"
  if [ ! -f "$TARGET_REPO/$GUIDANCE_REL" ] && [ -f "$TARGET_REPO/guidance/$GUIDANCE_REL" ]; then
    GUIDANCE_REL="guidance/$GUIDANCE_REL"
  fi
  GUIDANCE_PATH="$TARGET_REPO/$GUIDANCE_REL"
  if [ -f "$GUIDANCE_PATH" ]; then
    if ! $DRY_RUN; then
      if ! grep -qF "$SUMMARY" "$GUIDANCE_PATH" 2>/dev/null; then
        printf "\n### %s (%s)\n%s\n" "$SUMMARY" "$DATE" "$BODY" >> "$GUIDANCE_PATH"
        # --only: see the note above; never sweep a concurrent session's staged work.
        (cd "$TARGET_REPO" && git add "$GUIDANCE_REL" && git commit --only "$GUIDANCE_REL" -m "guidance: $SUMMARY" && git push -u origin HEAD) 2>/dev/null || true
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
