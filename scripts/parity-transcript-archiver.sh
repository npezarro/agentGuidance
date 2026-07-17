#!/usr/bin/env bash
# parity-transcript-archiver.sh -- preserve transcripts of parity-A/B sessions
# before Claude Code's transcript rotation deletes them.
#
# Why: the interactive parity A/B (hooks/parity-layer-injection.sh) logs arm
# assignments in interactive-arms.jsonl, but outcomes are computed by joining
# those session ids to ~/.claude/projects/*/<sid>.jsonl -- and ~80%+ of
# transcripts eventually rotate away (two A/B sessions were already lost by
# 2026-07-16). This copies every logged session's transcript into the archive
# dir; scripts/parity-arm-analyzer.py falls back to the archive when the live
# transcript is gone.
#
# Runs hourly via the privateContext jobs registry. Re-copies while a session
# is still growing (live file larger than the archived copy), so the archive
# converges to the final transcript. Idempotent; no secrets; local-only output
# (transcripts are private -- the archive dir must never be pushed to any repo).

set -uo pipefail

TELEMETRY_FILE="${PARITY_TELEMETRY_FILE:-$HOME/.claude/parity-telemetry/interactive-arms.jsonl}"
ARCHIVE_DIR="${PARITY_ARCHIVE_DIR:-$HOME/.claude/parity-telemetry/transcripts}"
PROJECTS_DIR="$HOME/.claude/projects"

[ -f "$TELEMETRY_FILE" ] || { echo "$(date -u +%FT%TZ) no telemetry file; nothing to archive"; exit 0; }
mkdir -p "$ARCHIVE_DIR"

new=0 updated=0 current=0 missing=0
while IFS= read -r sid; do
  [ -n "$sid" ] || continue
  live="$(find "$PROJECTS_DIR" -maxdepth 2 -name "$sid.jsonl" -print -quit 2>/dev/null)"
  arch="$ARCHIVE_DIR/$sid.jsonl"
  if [ -z "$live" ]; then
    # rotated before capture (or never local); archived copy, if any, is final
    [ -f "$arch" ] || missing=$((missing+1))
    continue
  fi
  if [ ! -f "$arch" ]; then
    cp "$live" "$arch" && new=$((new+1))
  elif [ "$(stat -c %s "$live")" -gt "$(stat -c %s "$arch")" ]; then
    cp "$live" "$arch" && updated=$((updated+1))
  else
    current=$((current+1))
  fi
done < <(jq -r '.session_id // empty' "$TELEMETRY_FILE" 2>/dev/null | sort -u)

echo "$(date -u +%FT%TZ) archived new=$new updated=$updated current=$current lost_before_capture=$missing dir=$ARCHIVE_DIR"
exit 0
