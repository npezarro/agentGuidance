# context.md

## Last Updated
2026-03-04 — Removed Discord Integration section (moved to centralDiscord repo)

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across 30 repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft on YOUR_DOMAIN
- Posts render as proper HTML (markdown conversion), include a "Previously on..." recap, and are filed under the "Claude Journals" category
- All 30 repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks
- User-level hooks on the VM (`~/.claude/settings.json`) also fetch from GitHub at runtime
- Agent rules require a descriptive opening heading that doubles as the WP post title

## Recent Changes
- Removed Discord Integration section from `agent.md` — moved to `centralDiscord/docs/discord-agent-guide.md` to keep agent.md focused on universal rules
- Added "Regression & Functional Verification" subsection under Testing — agents must verify all critical user flows after changes, not just run unit tests
- Rewrote auto-posting rules in `agent.md`: responses must be written as first-person blog posts, not terse CLI summaries
- Removed rigid "The Ask / What Happened" template from `post-to-wordpress.sh` — response is the post
- Added `md_to_html()` markdown-to-HTML converter to the hook (uses python-markdown, stdlib fallback)
- Added "Previously on..." recap section that pulls last 3 private posts from WP API
- Added "Claude Journals" category (ID 16) to all auto-posts
- Improved title generation: derives from response heading/first sentence, not user prompt
- Fixed user-level Stop hook to fetch from GitHub instead of stale local copy
- Made `context.md` updates mandatory in the git workflow and commit checklist
2026-03-07 — Elevated progress.md to core mandatory instruction; removed Recent Changes from context.md spec

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft and a Discord embed
- Discord Integration section in agent.md is a slim reference — full details live in the private Discord bot repo's docs
- `progress.md` is a mandatory core instruction — every commit must include a progress.md entry
- `context.md` is now a pure current-state snapshot — "Recent Changes" removed (history lives in `progress.md`)
- All repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks

## Open Work
- Propagation needed: run `scripts/propagate-hooks.sh` after merging to push updated CLAUDE.md to all repos
- GitHub PAT exposed in git remote URL — must be rotated immediately

## Environment Notes
- **Repo:** PUBLIC — do not commit secrets or infrastructure details
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` to all repos

## Active Branch
agent/remove-discord-from-agent-rules
agent/add-regression-testing-guidance
claude/progress-md-core-instruction

---
**For change history**, see `progress.md`.
