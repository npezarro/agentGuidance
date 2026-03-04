# context.md

## Last Updated
2026-03-04 — Expanded Discord Integration section for full agent-server interaction

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across 30 repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft on pezant.ca and a Discord embed in #claude-agent-logs
- Discord Integration section now covers: auto-posting mechanics, manual posting, per-project channels, specialist agents, inter-agent coordination, and #requests usage
- All 30 repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks
- User-level hooks on the VM (`~/.claude/settings.json`) also fetch from GitHub at runtime

## Recent Changes
- Expanded Discord Integration section in `agent.md` — added subsections for auto-posting mechanics, manual posting, receiving/responding to requests, specialist agent roles, and inter-agent coordination
- Agents are now explicitly encouraged to create per-project channels and use specialist agents when appropriate
- Added detailed specialist agent role descriptions (code reviewer, devops, architecture, performance, test engineer)
- Added inter-agent coordination guidelines for avoiding conflicts and sharing discoveries
- Previous: Added Regression & Functional Verification subsection under Testing
- Previous: Rewrote auto-posting rules — responses as first-person blog posts

## Open Work
- Specialist agent system prompts not yet formalized in centralDiscord — bot spawns generic `claude -p` sessions; role-specific system prompts would improve specialist quality
- Per-project channel creation works via #requests but could be streamlined with a dedicated bot command
- Propagation needed: run `scripts/propagate-hooks.sh` after merging to push updated CLAUDE.md to all 30 repos

## Environment Notes
- **Repo:** github.com/npezarro/agentGuidance
- **Fetched from:** `https://raw.githubusercontent.com/npezarro/agentGuidance/main/` (CDN has ~5 min cache)
- **WordPress site:** pezant.ca (REST API at `/wp-json/wp/v2/posts`)
- **WP credentials:** stored in `/home/generatedByTermius/.env` (WP_USER, WP_APP_PASSWORD)
- **Discord bot:** ClaudeAgent#8311, PM2 process `claude-bot`, code at `/home/generatedByTermius/centralDiscord`
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` to all repos

## Active Branch
agent/expand-discord-integration
