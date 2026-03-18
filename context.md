# context.md

## Last Updated
2026-03-18 | Added retry logic for PR creation to prevent "create manually" fallback messages

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

## Open Work
- promptlibrary PR #5 ("Claude/Prompt Lifecycle") was closed on 2026-03-15 due to stale conflicts across extension files; commits preserved in PR history for future cherry-picking if needed
- Several repos still have local branches checked out on old feature branches (not blocking)

## Environment Notes
- **Repo:** PUBLIC; do not commit secrets or infrastructure details
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` + `.gitattributes` to all repos

## Active Branch
claude/reliable-pr-creation

---
**For change history**, see `progress.md`.
