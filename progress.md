# Progress Log

> Continuously updated log of all work done on this project. Add entries in reverse chronological order (newest first). One entry per PR, deploy, or significant change. Keep entries concise — 1-2 lines max.
>
> **Update rules:**
> - Add an entry for every merged PR or significant commit
> - Add an entry for every deploy
> - Log infrastructure changes (env vars, server config, deps)
> - Never include secrets, credentials, or .env contents
> - Format: `YYYY-MM-DD | <type> | <description>`

## Log

| Date | Type | Description |
|------|------|-------------|
| 2026-04-23 | feat | Add git-push-reminder.sh PostToolUse hook: fires on Edit/Write, reminds agent to commit+push when file has uncommitted changes in a git repo. Added to ~/.claude/settings.json |
| 2026-04-19 | feat | Broaden auto-file-links.sh to post links for all .md files on push (was limited to output/report dirs) |
| 2026-03-20 | docs | Overhaul guidance/testing.md with testing pyramid strategy (failure audit, contract tests, integration tests, smoke tests, browser tests); add templates/failure-audit.md |
| 2026-03-20 | feat | Parameterize send-email.js sender name (arg or SENDER_NAME env var), fix .env load order so ALERT_EMAIL resolves in cron context |
| 2026-03-19 | feat | Add recurring-tasks infrastructure: shared runner.sh with flock locking, scoped permissions, Discord notifications; crontab generator |
| 2026-03-18 | fix | Add retry logic for PR creation in agent.md: wait for branch registration, retry gh pr create 3x, never fall back to manual URLs |
| 2026-03-17 | feat | Add shared ESLint 9 flat config (eslint/) with base JS rules and optional TypeScript overrides for cross-repo use |
| 2026-03-17 | docs | Confirmed promptlibrary PR #5 already closed (2026-03-15) due to stale conflicts; updated context.md to reflect resolved status |
| 2026-03-14 | infra | Propagated `.gitattributes` with `merge=union` to all 15 repos on main; rebased and merged 19 of 20 conflicting PRs across 7 repos |
| 2026-03-14 | docs | Add Branch Hygiene section to Git Workflow: merge PRs promptly, rebase before opening PRs, clean up stale branches |
| 2026-03-14 | fix | Prevent merge conflicts: add `.gitattributes` with `merge=union` for progress.md, reduce context.md update frequency to final-branch-commit only, add `.gitattributes` to self-review checklist, update propagation script |
| 2026-03-14 | docs | Remove all em dashes from agent.md, add no-em-dash writing convention to Communication section |
| 2026-03-10 | feat | Add real-world examples to templates/context.md and templates/progress.md, 3 project-type examples each (bot, web app, CLI tool), all sanitized |
| 2026-03-07 | feat | Add three guidance files (session-lifecycle, resource-awareness, process-hygiene) distilled from Discord bot development; expand agent.md with post-deploy verification, logs-first debugging, and multi-destination output design |
| 2026-03-07 | docs | Elevate progress.md to mandatory core instruction — every commit requires an entry; remove "Recent Changes" from context.md spec to eliminate dual-source drift |
| 2026-03-07 | refactor | Extract Discord details from agent.md to discord-bot repo, add progress.md system |
| 2026-03-05 | PR #11 | Agent/Public Repo Warning — duplicate PR merged |
| 2026-03-04 | PR #10 | Add public repo warning and expand Security section |
| 2026-03-04 | PR #7 | Expand Discord Integration for full agent-server interaction |
| 2026-03-04 | PR #6 | Agent/Expand Discord Integration |
| 2026-03-04 | PR #5 | Add Discord Integration section to global agent rules |
| 2026-03-04 | PR #3 | Add Discord stop hook for agent turn logging |
| 2026-03-04 | PR #2 | Add Regression & Functional Verification to Testing rules |
| 2026-03-01 | PR #1 | Comprehensive guidance improvements with modular sub-guidance and templates |
