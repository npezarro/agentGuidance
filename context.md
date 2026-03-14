# context.md

## Last Updated
2026-03-14 | Merged all outstanding PRs, propagated .gitattributes, added Branch Hygiene rules

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
- promptlibrary PR #5 ("Claude/Prompt Lifecycle") has complex code conflicts in extension files; needs manual resolution
- Several repos still have local branches checked out on old feature branches (not blocking)

## Environment Notes
- **Repo:** PUBLIC; do not commit secrets or infrastructure details
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` + `.gitattributes` to all repos

## Active Branch
main

---
**For change history**, see `progress.md`.
