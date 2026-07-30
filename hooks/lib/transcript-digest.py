#!/usr/bin/env python3
"""Build a compact evidence digest from a Claude Code session transcript.

WHY THIS EXISTS
The session scorer used to receive `last_assistant_message` (the final chat
message) and nothing else. That is a *summary of* the work, not the work, so the
scorer could not observe the very rules it was grading:

  - verify_before_asserting  -- needs to know whether a verification command
                                actually ran, which lives in tool_use records
  - test_before_reporting    -- same
  - push_before_posting      -- needs the git push invocation
  - multi_destination_learning / guidance_to_repo_files
                             -- needs the list of files actually written

Grading prose instead of behavior produced a bimodal 0/100 score distribution and
made verify_before_asserting the most-"violated" rule in the corpus, because a
summary can only ever show whether the agent *claimed* to verify.

This emits the behavioral evidence first (commands, files touched) and the final
message last, because supervisor/score.sh truncates its input with `head -c`, so
the front of the digest is the part guaranteed to survive.

Usage: transcript-digest.py <transcript.jsonl> [byte_budget]
Writes the digest to stdout. Exits 1 if the transcript is unusable.
"""
import json
import os
import sys
from collections import Counter

# Bash commands that constitute real verification evidence. Used only to
# surface a "did any verification actually run" line; the scorer still judges.
VERIFY_HINTS = (
    "curl", "npm test", "npm run build", "jest", "pytest", "pm2 status",
    "pm2 list", "docker ps", "git log", "git status", "bash -n", "node -e",
    "systemctl status", "gh pr", "wc -c", "grep -c",
)


def load(path):
    out = []
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def blocks(entry):
    """Yield content blocks from a transcript entry, tolerating both shapes."""
    msg = entry.get("message")
    if not isinstance(msg, dict):
        return
    content = msg.get("content")
    if isinstance(content, list):
        for b in content:
            if isinstance(b, dict):
                yield b


def text_of(entry):
    parts = []
    for b in blocks(entry):
        if b.get("type") == "text" and b.get("text"):
            parts.append(b["text"])
    msg = entry.get("message")
    if not parts and isinstance(msg, dict) and isinstance(msg.get("content"), str):
        parts.append(msg["content"])
    return "\n".join(parts)


def one_line(s, cap=160):
    s = " ".join(str(s).split())
    return s[:cap] + ("..." if len(s) > cap else "")


def main():
    if len(sys.argv) < 2:
        print("usage: transcript-digest.py <transcript.jsonl> [byte_budget]", file=sys.stderr)
        return 1
    path = sys.argv[1]
    budget = int(sys.argv[2]) if len(sys.argv) > 2 else 10000
    if not os.path.isfile(path):
        return 1

    entries = load(path)
    if not entries:
        return 1

    tools = Counter()
    commands = []      # bash command strings, in order
    written = []       # files created/edited
    read_files = []
    n_user = n_asst = 0

    for e in entries:
        etype = e.get("type")
        if etype == "user":
            n_user += 1
        elif etype == "assistant":
            n_asst += 1
        for b in blocks(e):
            if b.get("type") != "tool_use":
                continue
            name = b.get("name") or "?"
            tools[name] += 1
            inp = b.get("input") or {}
            if not isinstance(inp, dict):
                continue
            if name == "Bash" and inp.get("command"):
                commands.append(one_line(inp["command"], 200))
            elif name in ("Write", "Edit", "NotebookEdit") and inp.get("file_path"):
                written.append(str(inp["file_path"]))
            elif name == "Read" and inp.get("file_path"):
                read_files.append(str(inp["file_path"]))

    if not tools and n_asst == 0:
        return 1

    # Final assistant message: what the agent claimed it did.
    final = ""
    for e in reversed(entries):
        if e.get("type") == "assistant":
            t = text_of(e)
            if t.strip():
                final = t.strip()
                break

    verifications = [c for c in commands if any(h in c for h in VERIFY_HINTS)]
    pushes = [c for c in commands if "git push" in c]
    commits = [c for c in commands if "git commit" in c]

    L = []
    a = L.append
    a("=== SESSION EVIDENCE DIGEST ===")
    a("This is the ACTUAL tool-call record, not the agent's self-report.")
    a("Judge the rules against what ran here; the agent's claims are at the end.")
    a("")
    a("turns: %d user / %d assistant | tool calls: %d"
      % (n_user, n_asst, sum(tools.values())))
    a("tools: " + (", ".join("%s=%d" % kv for kv in tools.most_common()) or "none"))
    a("verification-shaped commands: %d | git commit: %d | git push: %d"
      % (len(verifications), len(commits), len(pushes)))
    a("")

    if written:
        a("=== FILES WRITTEN / EDITED (%d) ===" % len(written))
        seen = []
        for f in written:
            if f not in seen:
                seen.append(f)
        L.extend("  " + f for f in seen[:40])
        a("")

    uniq_reads = []
    for f in read_files:
        if f not in uniq_reads:
            uniq_reads.append(f)

    def build_head(cmd_limit, read_limit):
        H = list(L)
        if commands:
            H.append("=== COMMANDS RUN, in order (%d) ===" % len(commands))
            H.extend("  $ " + c for c in commands[:cmd_limit])
            if len(commands) > cmd_limit:
                H.append("  ... %d more" % (len(commands) - cmd_limit))
            H.append("")
        if uniq_reads and read_limit:
            H.append("=== FILES READ (%d unique) ===" % len(uniq_reads))
            H.extend("  " + f for f in uniq_reads[:read_limit])
            H.append("")
        return "\n".join(H)

    # Hard-cap the whole digest: shrink the low-value sections (reads first,
    # then the command tail) until the behavioral evidence plus a usable slice
    # of the final message fits the budget.
    head = build_head(60, 25)
    for cmd_limit, read_limit in ((60, 25), (40, 10), (25, 0), (15, 0), (8, 0)):
        head = build_head(cmd_limit, read_limit)
        if len(head) <= budget * 0.75:
            break

    # Final message gets whatever budget is left, so the behavioral evidence
    # above is never the part that gets cut.
    label = "=== AGENT'S FINAL MESSAGE (its own claims; verify against the above) ===\n"
    remaining = max(400, budget - len(head) - len(label) - 20)
    if len(final) > remaining:
        final = final[:remaining] + "\n[...truncated]"
    out = head + label + final
    # Budget is a BYTE budget (score.sh truncates with `head -c`), and slicing a
    # str slices characters, so multi-byte content would sail past the cap.
    raw = out.encode("utf-8")
    if len(raw) > budget:
        out = raw[:budget].decode("utf-8", errors="ignore")

    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
