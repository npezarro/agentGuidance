#!/usr/bin/env python3
"""Freeze the candidate set for xp-001 (memory-lazy-tier).

Candidates are the entries we would demote out of the always-loaded index:
reference-shaped memories (project_*, reference_*) with ZERO read history
across every session transcript on this host.

Deliberately excluded: feedback_, rule_, pattern_, learning_. Those work by
being PRESENT in context, not by being opened, so a read count of zero says
nothing about their value. Using read counts to prune them would be measuring
the wrong thing, confidently.

Usage:  build-lazy-candidates.py [--out PATH] [--index PATH]
"""
import argparse, glob, json, os, re, sys

LAZY_PREFIXES = ("project_", "reference_")
HOME = os.path.expanduser("~")
DEFAULT_INDEX = f"{HOME}/.claude/projects/-mnt-c-Users-npeza/memory/MEMORY.md"
DEFAULT_OUT = f"{HOME}/.claude/memory-lazy-candidates.txt"
DEFAULT_INDEX_OUT = f"{HOME}/.claude/memory-lazy-index.txt"

ap = argparse.ArgumentParser()
ap.add_argument("--index", default=DEFAULT_INDEX)
ap.add_argument("--out", default=DEFAULT_OUT)
ap.add_argument("--index-out", default=DEFAULT_INDEX_OUT)
args = ap.parse_args()

# 1. Every entry in the always-loaded index, in compact "name: hook" format.
entries = {}
for line in open(args.index, encoding="utf-8"):
    line = line.rstrip("\n")
    if line.startswith("#") or not line:
        continue
    m = re.match(r"^([A-Za-z0-9][A-Za-z0-9_.\-]*):\s*(.*)$", line)
    if m:
        entries[m.group(1)] = m.group(2)

# 2. Read history. Count ONLY Read tool calls (a file_path in a tool_use block).
#    Counting raw name occurrences would count the index injection itself, so
#    every memory would look "used" once per session and the measurement would
#    be of its own shadow.
reads = {}
for path in glob.glob(f"{HOME}/.claude/projects/*/*.jsonl"):
    try:
        with open(path, errors="ignore") as fh:
            for line in fh:
                if '"file_path"' not in line:
                    continue
                for m in re.finditer(r'"file_path":"[^"]*/memory/([^"/]+)\.md"', line):
                    reads[m.group(1)] = reads.get(m.group(1), 0) + 1
    except OSError:
        continue

candidates = {n: h for n, h in entries.items()
              if n.startswith(LAZY_PREFIXES) and reads.get(n, 0) == 0}

with open(args.out, "w", encoding="utf-8") as fh:
    fh.write("# xp-001 candidate set: index entries eligible for the lazy tier.\n")
    fh.write("# reference-shaped (project_/reference_) AND never opened in any session.\n")
    fh.write("# Frozen at test start; do not edit while the experiment is running.\n")
    for n in sorted(candidates):
        fh.write(f"{n}: {candidates[n]}\n")

# The retriever SCORES against every index entry, not just the demote candidates.
# Scoring only the candidates made the primary metric unmeasurable by construction:
# candidates are selected for having zero reads, so "was a candidate opened?" is an
# event with an observed rate of 0 in 4,225 sessions. Scoring the full index lets
# recall be measured on the memories that DO get opened (~3.7% of sessions), which
# is the transferable question: does keyword retrieval find a wanted memory at all?
with open(args.index_out, "w", encoding="utf-8") as fh:
    fh.write("# xp-001 scoring set: EVERY index entry.\n")
    fh.write("# Recall is measured here; lazy-tier injection COST is measured on the\n")
    fh.write("# candidate subset only (see memory-lazy-candidates.txt).\n")
    for n in sorted(entries):
        fh.write(f"{n}: {entries[n]}\n")

kept = len(entries) - len(candidates)
print(f"index entries          : {len(entries)}")
print(f"lazy candidates        : {len(candidates)}  -> {args.out}")
print(f"stays always-loaded    : {kept}")
print(f"scoring set (full index): {len(entries)}  -> {args.index_out}")
print(f"transcripts scanned    : {len(glob.glob(f'{HOME}/.claude/projects/*/*.jsonl'))}")
print(f"memories with reads    : {len(reads)}")
