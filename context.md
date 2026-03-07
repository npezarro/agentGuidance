# context.md

## Last Updated
2026-03-07 — Extracted Discord details from agent.md to centralDiscord repo, added progress.md system

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft on YOUR_DOMAIN and a Discord embed in #claude-agent-logs
- Discord Integration section in agent.md is now a slim reference — full details live in centralDiscord's `docs/discord-agent-guide.md`
- New `progress.md` system: every repo now has a progress log tracking PRs, deploys, and infra changes over time
- All repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks

## Recent Changes
- Extracted Discord-specific details (Guild IDs, channel IDs, bot details, specialist agents, per-project channels) from `agent.md` into `centralDiscord/docs/discord-agent-guide.md`
- Added `progress.md` template to `templates/` and Progress Log section to `agent.md` rules
- Seeded `progress.md` in all 5 local repos (agentGuidance, centralDiscord, groceryGenius, pezantTools, assortedLLMTasks)
- Previous: Added public repo warning and expanded Security section

## Open Work
- Propagation needed: run `scripts/propagate-hooks.sh` after merging to push updated CLAUDE.md to all repos
- Repos not cloned locally (runEvaluator, runCoach, LIScraper, etc.) still need `progress.md` added

## Environment Notes
- **Repo:** github.com/npezarro/agentGuidance (PUBLIC)
- **Fetched from:** `https://raw.githubusercontent.com/npezarro/agentGuidance/main/` (CDN has ~5 min cache)
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` to all repos

## Active Branch
agent/public-repo-warning
