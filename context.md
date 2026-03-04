# context.md

## Last Updated
2026-03-04 — Added public repo warning and expanded Security section

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across 30 repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft on YOUR_DOMAIN and a Discord embed in #claude-agent-logs
- Discord Integration section now covers: auto-posting mechanics, manual posting, per-project channels, specialist agents, inter-agent coordination, and #requests usage
- All 30 repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks
- User-level hooks on the VM (`~/.claude/settings.json`) also fetch from GitHub at runtime

## Recent Changes
- Added prominent public repo warning banner at top of `agent.md` and expanded Security section with audit checklist, infrastructure detail restrictions, and incident response guidance
- Previous: Expanded Discord Integration section — auto-posting mechanics, manual posting, specialist agents, inter-agent coordination
- Previous: Added Regression & Functional Verification subsection under Testing
- Previous: Rewrote auto-posting rules — responses as first-person blog posts

## Open Work
- **Discord section contains real infrastructure details** (Guild ID, channel IDs, server paths, domain names) that are now public — consider moving these to a private config or redacting them from `agent.md`
- Specialist agent system prompts not yet formalized in discord-bot
- Propagation needed: run `scripts/propagate-hooks.sh` after merging to push updated CLAUDE.md to all 30 repos

## Environment Notes
- **Repo:** github.com/npezarro/agentGuidance
- **Fetched from:** `https://raw.githubusercontent.com/npezarro/agentGuidance/main/` (CDN has ~5 min cache)
- **WordPress site:** YOUR_DOMAIN (REST API at `/wp-json/wp/v2/posts`)
- **WP credentials:** stored in `$HOME/.env` (WP_USER, WP_APP_PASSWORD)
- **Discord bot:** YourBot#0000, PM2 process `your-bot-process`, code at `$HOME/discord-bot`
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` to all repos

## Active Branch
agent/public-repo-warning
