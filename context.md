# context.md

## Last Updated
2026-03-20 | Removed job-search content from public repo; moved to privateContext

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft and a Discord embed
- `progress.md` is a mandatory core instruction; every commit must include a progress.md entry
- **`progress.md` uses `merge=union`** via `.gitattributes` across all 15 repos to prevent merge conflicts
- **`context.md` update frequency reduced**: now only updated on final branch commit (before PR) or during Session Wrap-Up
- **Branch Hygiene rules** added: merge PRs in the same session, rebase before opening, clean up stale branches
- No em dashes allowed in any agent output (Communication rule)
- 8 guidance files in `guidance/` directory
- Templates in `templates/` include filled-in examples from real projects (sanitized)
- **`recurring-tasks/`**: shared runner with flock-based locking, scoped permissions, Discord notifications, and crontab generator (task configs moved to privateContext)

## Open Work
- promptlibrary PR #5 ("Claude/Prompt Lifecycle") was closed on 2026-03-15 due to stale conflicts across extension files; commits preserved in PR history for future cherry-picking if needed
- Several repos still have local branches checked out on old feature branches (not blocking)
- Recurring tasks infrastructure is generic; task configs and prompts live in `~/repos/privateContext/recurring-tasks/`

## Environment Notes
- **Repo:** PUBLIC; do not commit secrets or infrastructure details
- **Private context:** `~/repos/privateContext` (private repo) contains account details, infra specifics, env var lists, pending manual actions, and completed work log. Consult it for sensitive information instead of storing it here.
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` + `.gitattributes` to all repos
- **Recurring tasks:** `recurring-tasks/runner.sh` is the shared runner; task configs and prompts live in `~/repos/privateContext/recurring-tasks/`

## Active Branch
main

---
**For change history**, see `progress.md`.
