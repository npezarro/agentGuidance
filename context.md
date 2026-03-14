# context.md

## Last Updated
2026-03-14 | Merged merge-conflict prevention, em-dash convention, and .gitattributes propagation

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft and a Discord embed
- `progress.md` is a mandatory core instruction; every commit must include a progress.md entry
- **`progress.md` uses `merge=union`** via `.gitattributes` to prevent merge conflicts when multiple branches add entries concurrently
- **`context.md` update frequency reduced**: now only updated on final branch commit (before PR) or during Session Wrap-Up, not on every intermediate commit
- `context.md` is a pure current-state snapshot; history lives in `progress.md`
- All repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks
- No em dashes allowed in any agent output (Communication rule)
- 8 guidance files in `guidance/` directory
- Templates in `templates/` include filled-in examples from real projects (sanitized)

## Open Work
- Propagation needed: run `scripts/propagate-hooks.sh` after merging to push updated `.gitattributes`, settings, and CLAUDE.md to all repos
- 20 open PRs across 7 repos need rebasing and merging (all currently conflicting)

## Environment Notes
- **Repo:** PUBLIC; do not commit secrets or infrastructure details
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` + `.gitattributes` to all repos

## Active Branch
claude/merge-prevention-combined

---
**For change history**, see `progress.md`.
