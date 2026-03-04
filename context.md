# context.md

## Last Updated
2026-03-04 — Added Regression & Functional Verification section to Testing

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across 30 repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft on pezant.ca
- Posts render as proper HTML (markdown conversion), include a "Previously on..." recap, and are filed under the "Claude Journals" category
- All 30 repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks
- User-level hooks on the VM (`~/.claude/settings.json`) also fetch from GitHub at runtime
- Agent rules require a descriptive opening heading that doubles as the WP post title

## Recent Changes
- Added "Regression & Functional Verification" subsection under Testing — agents must verify all critical user flows after changes, not just run unit tests
- Rewrote auto-posting rules in `agent.md`: responses must be written as first-person blog posts, not terse CLI summaries
- Removed rigid "The Ask / What Happened" template from `post-to-wordpress.sh` — response is the post
- Added `md_to_html()` markdown-to-HTML converter to the hook (uses python-markdown, stdlib fallback)
- Added "Previously on..." recap section that pulls last 3 private posts from WP API
- Added "Claude Journals" category (ID 16) to all auto-posts
- Improved title generation: derives from response heading/first sentence, not user prompt
- Fixed user-level Stop hook to fetch from GitHub instead of stale local copy
- Made `context.md` updates mandatory in the git workflow and commit checklist

## Open Work
- None currently — system is stable and propagated

## Environment Notes
- **Repo:** github.com/npezarro/agentGuidance
- **Fetched from:** `https://raw.githubusercontent.com/npezarro/agentGuidance/main/` (CDN has ~5 min cache)
- **WordPress site:** pezant.ca (REST API at `/wp-json/wp/v2/posts`)
- **WP credentials:** stored in `/home/generatedByTermius/.env` (WP_USER, WP_APP_PASSWORD)
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` to all repos

## Active Branch
agent/add-regression-testing-guidance
