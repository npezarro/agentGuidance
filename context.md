# context.md

## Last Updated
2026-03-10 — Switch fetch-rules.sh to local-first with cron sync

## Current State
- Central source of truth for all Claude Code agent rules, hooks, and templates across repos
- Auto-posting system is live: every Claude Code response becomes a private WordPress draft and a Discord embed
- `progress.md` is a mandatory core instruction — every commit must include a progress.md entry
- `context.md` is now a pure current-state snapshot — history lives in `progress.md`
- All repos have `.claude/settings.json` with SessionStart (fetch rules) and Stop (auto-post) hooks
- **Rule delivery is now local-first**: `fetch-rules.sh` reads from the local agentGuidance clone, falls back to curl, then to a hardcoded minimal policy. No session ever starts without rules.
- **Cron sync**: `scripts/sync-guidance.sh` runs every 15 minutes via cron to keep the local clone current with `--ff-only`
- **Version traceability**: every session's context includes the git SHA and branch of the agent.md it loaded
- 8 guidance files in `guidance/` directory
- Templates in `templates/` now include filled-in examples from real projects (sanitized)

## Open Work
- Propagation needed: run `scripts/propagate-hooks.sh` after merging to push updated templates to all repos (template now uses local-first, no more `curl | bash` Stop hooks)
- Review `skipDangerousModePermissionPrompt: true` in global settings — document rationale or consider removing

## Environment Notes
- **Repo:** PUBLIC — do not commit secrets or infrastructure details
- **Propagation script:** `scripts/propagate-hooks.sh` pushes `.claude/settings.json` + `CLAUDE.md` to all repos
- **Sync cron:** `*/15 * * * *` runs `scripts/sync-guidance.sh`, logs to `/var/log/agentguidance-sync.log`

## Active Branch
claude/template-exemplification

---
**For change history**, see `progress.md`.
