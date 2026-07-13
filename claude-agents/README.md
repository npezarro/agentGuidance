# Claude Code Subagent Definitions

Version-controlled copies of the custom subagent definitions that live at `~/.claude/agents/` (the active location Claude Code reads from). These were previously unversioned and live-only; this directory is their backup and source of history.

Each `<name>.md` defines a specialist subagent (frontmatter `name` + `description`, optional `model`, optional `allowed-tools`, then the system prompt). The former `profiles/` persona system (persistent identity + experience logs) was removed 2026-07-01; definitions are now self-contained. History: see git before commit c5bc0c6.

## Current agents
- **architect** — system design, architecture decisions, migration planning
- **debugger** — bug hunting, error analysis, root cause
- **doc-sync** — CLAUDE.md freshness / documentation drift
- **propagation** — routes learnings to all destinations
- **quick-search** — fast cheap codebase search (Haiku-pinned)
- **reviewer** — code review and security audit
- **security** — threat modeling, auth, secrets hygiene, hardening
- **verifier** — independent skeptic that refutes "it works / fixed / passing" claims before they are reported or merged

## Sync (mirrors the claude-skills pattern)
Edit in this repo, then copy to the active location, commit, and push here for history:

```bash
# repo -> active
cp ~/repos/agentGuidance/claude-agents/*.md ~/.claude/agents/
# active -> repo (capture live edits before committing)
cp ~/.claude/agents/*.md ~/repos/agentGuidance/claude-agents/
```

These are generic role prompts with no secrets, safe for this public repo. See `guidance/when-to-fan-out.md` for when to actually spawn these subagents.
