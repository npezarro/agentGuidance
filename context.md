# context.md

## Last Updated
2026-03-10 — Fix merge conflicts on context.md/progress.md via .gitattributes and reduced update frequency

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft and a Discord embed
- `progress.md` is a mandatory core instruction — every commit must include a progress.md entry
- **`progress.md` uses `merge=union`** via `.gitattributes` to prevent merge conflicts when multiple branches add entries concurrently
- **`context.md` update frequency reduced** — now only updated on final branch commit (before PR) or during Session Wrap-Up, not on every intermediate commit
- `context.md` is a pure current-state snapshot — history lives in `progress.md`
- All repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks
- Rule delivery is local-first: `fetch-rules.sh` reads from the local agentGuidance clone, falls back to curl
- Cron sync: `scripts/sync-guidance.sh` runs every 15 minutes
- Version traceability: every session's context includes the git SHA and branch of the agent.md it loaded
- 8 guidance files in `guidance/` directory
- Templates in `templates/` now include filled-in examples from real projects (sanitized)

## Open Work
- Propagation needed: run `scripts/propagate-hooks.sh` after merging to push updated `.gitattributes`, settings, and CLAUDE.md to all repos
- Review `skipDangerousModePermissionPrompt: true` in global settings — document rationale or consider removing

## Environment Notes
- **Repo:** PUBLIC — do not commit secrets or infrastructure details
- **Propagation script:** `scripts/propagate-hooks.sh` now pushes `.claude/settings.json` + `CLAUDE.md` + `.gitattributes` to all repos
- **Sync cron:** `*/15 * * * *` runs `scripts/sync-guidance.sh`, logs to `/var/log/agentguidance-sync.log`

## Active Branch
claude/template-exemplification

---
**For change history**, see `progress.md`.
