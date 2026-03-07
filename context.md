# context.md

## Last Updated
2026-03-07 — Purged private details from public repo and git history

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft and a Discord embed
- Discord Integration section in agent.md is a slim reference — full details live in the private Discord bot repo's docs
- `progress.md` system: every repo now has a progress log tracking PRs, deploys, and infra changes over time
- All repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks

## Recent Changes
- Purged all private infrastructure details (domain, hostnames, paths, usernames) from public repo and git history
- Extracted Discord-specific details from `agent.md` into private bot repo
- Added `progress.md` template and Progress Log section to `agent.md` rules

## Open Work
- Propagation needed: run `scripts/propagate-hooks.sh` after merging to push updated CLAUDE.md to all repos
- GitHub PAT exposed in git remote URL — must be rotated immediately

## Environment Notes
- **Repo:** PUBLIC — do not commit secrets or infrastructure details
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` to all repos

## Active Branch
main
