# context.md

## Last Updated
2026-03-10 — Added real-world examples to context.md and progress.md templates

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft and a Discord embed
- `progress.md` is a mandatory core instruction — every commit must include a progress.md entry
- `context.md` is now a pure current-state snapshot — history lives in `progress.md`
- All repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks
- 8 guidance files in `guidance/` directory
- Templates in `templates/` now include filled-in examples from real projects (sanitized)

## Open Work
- Propagation needed: run `scripts/propagate-hooks.sh` after merging to push updated CLAUDE.md to all repos

## Environment Notes
- **Repo:** PUBLIC — do not commit secrets or infrastructure details
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` to all repos

## Active Branch
claude/template-exemplification

---
**For change history**, see `progress.md`.
