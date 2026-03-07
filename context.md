# context.md

## Last Updated
2026-03-07 — Added three new guidance files from Discord learnings; expanded agent.md deployment, debugging, and auto-posting sections

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft and a Discord embed
- Discord Integration section in agent.md is a slim reference — full details live in the private Discord bot repo's docs
- `progress.md` is a mandatory core instruction — every commit must include a progress.md entry
- `context.md` is now a pure current-state snapshot — "Recent Changes" removed (history lives in `progress.md`)
- All repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks
- Three new guidance files added: `session-lifecycle.md`, `resource-awareness.md`, `process-hygiene.md`
- `agent.md` expanded: post-deploy verification protocol, logs-first debugging, multi-destination output design

## Open Work
- Propagation needed: run `scripts/propagate-hooks.sh` after merging to push updated CLAUDE.md to all repos
- GitHub PAT exposed in git remote URL — must be rotated immediately

## Environment Notes
- **Repo:** PUBLIC — do not commit secrets or infrastructure details
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` to all repos

## Active Branch
claude/discord-learnings-guidance

---
**For change history**, see `progress.md`.
