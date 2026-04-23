# context.md

## Last Updated
2026-04-23 | Added git-push-reminder PostToolUse hook for Edit|Write

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft and a Discord embed
- `progress.md` is a mandatory core instruction; every commit must include a progress.md entry
- **`progress.md` uses `merge=union`** via `.gitattributes` across all 15 repos to prevent merge conflicts
- **`context.md` update frequency reduced**: now only updated on final branch commit (before PR) or during Session Wrap-Up
- **Branch Hygiene rules** added: merge PRs in the same session, rebase before opening, clean up stale branches
- No em dashes allowed in any agent output (Communication rule)
- **27 guidance files** in `guidance/` directory (including learning-capture, learning-agent, comprehensive-closeout)
- **agent.md at 78/100 lines** -- approaching ceiling (suggestion S2: extract Communication section when needed)
- Templates in `templates/` include filled-in examples from real projects (sanitized)
- **`recurring-tasks/`**: shared runner with flock-based locking, scoped permissions, Discord notifications, and crontab generator (task configs moved to privateContext)
- **Deep closeout process now requires context.md updates** for every touched repo (Step 5) and memory updates (Step 6) to bridge the gap between archive and handoff
- **post-closeout.sh** upgraded from truncated single embed to threaded chunking (full content, no loss)
- **auto-file-links.sh** broadened: now posts links for ALL .md files on push (excludes README/CHANGELOG/CLAUDE/MEMORY/config/.claude/)
- **git-push-reminder.sh** hook added: PostToolUse on Edit|Write, reminds agent to commit+push when writing to a git repo with uncommitted changes. Added to ~/.claude/settings.json. Skips memory, .claude, .env, credentials, and gitignored files.

## Open Work
- promptlibrary PR #5 ("Claude/Prompt Lifecycle") was closed on 2026-03-15 due to stale conflicts across extension files; commits preserved in PR history for future cherry-picking if needed
- Several repos still have local branches checked out on old feature branches (not blocking)
- Recurring tasks infrastructure is generic; task configs and prompts live in `~/repos/privateContext/recurring-tasks/`
- Learning agent PRs #67-71 all merged successfully
- S6 (branch collision risk) and S7 (deployment cross-ref) still open, minor

Full session closeout: `privateContext/deliverables/closeouts/2026-04-19-md-linker-file-links.md`

## Environment Notes
- **Repo:** PUBLIC; do not commit secrets or infrastructure details
- **Private context:** `~/repos/privateContext` (private repo) contains account details, infra specifics, env var lists, pending manual actions, and completed work log. Consult it for sensitive information instead of storing it here.
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` + `.gitattributes` to all repos
- **Recurring tasks:** `recurring-tasks/runner.sh` is the shared runner; task configs and prompts live in `~/repos/privateContext/recurring-tasks/`

## Active Branch
main

---
**For change history**, see `progress.md`.
