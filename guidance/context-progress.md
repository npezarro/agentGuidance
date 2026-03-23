# Context File and Progress Log

## Context File (`context.md`)

**This is not optional.** Every repo must have a `context.md` at its root. It is the handoff document between sessions: the way the next agent (or the next you) picks up where the last one left off. Treat it like a relay baton: if you don't pass it, the next runner starts blind.

### When to update
- **On the final commit of a branch** before creating a PR. Include the `context.md` update in that commit, not as a separate follow-up. Do not update on every intermediate commit (this causes merge conflicts when multiple branches are active).
- **During Session Wrap-Up**, even if you didn't push. If you investigated something, made a decision, or identified a blocker, capture it.
- **When you discover something about the environment** (a port, a config path, a quirk that's not documented yet).

### What to write
Keep it concise and current. This is a living status page, not a changelog.

```
# context.md
Last Updated: YYYY-MM-DD | one-line summary
Current State: what works, what's deployed, known issues
Open Work: blockers, unfinished tasks, decisions needed
Environment Notes: deploy target, process manager, ports, SSH user, config file paths
Active Branch: current working branch name
```

For change history, see `progress.md`.

### What NOT to include
- Credentials, API keys, tokens, passwords, or `.env` contents. Ever.
- Change history (that belongs in `progress.md`, not here). Keep `context.md` focused on current state.

### Environment Notes must include (when applicable)
- SSH user and hostname
- PM2 process name and port
- Web server config file path (e.g., Apache VirtualHost location)
- Base path if deployed to a subdirectory
- Database file path
- Node version, if it matters for the project

### If `context.md` doesn't exist yet
Create it from the template at `agentGuidance/templates/context.md`. Fill in what you can from the repo's config files, `package.json`, and environment. Don't leave placeholder comments; either fill in the value or remove the line.

## Progress Log (`progress.md`)

**This is not optional.** Every repo must have a `progress.md` at its root. This is the full chronological history of work done on the project. Unlike `context.md` (which is a mutable snapshot of current state), `progress.md` is an append-only chronological log that grows over time. Together they form a complete handoff system: `context.md` tells the next agent *where things stand*, `progress.md` tells them *how they got there*.

### When to update
- **Every commit that changes code or configuration.** Include the `progress.md` entry in the same commit.
- **Every merged PR**: add an entry with the PR number and a one-line description.
- **Every deploy**: note what was deployed and to where.
- **Infrastructure changes**: env vars added, server config changed, dependencies updated.
- **Significant commits** that don't go through PRs (hotfixes, config changes pushed directly).

### Format
Entries are reverse-chronological (newest first), one line per entry in a markdown table:

```
| Date | Type | Description |
|------|------|-------------|
| 2026-03-07 | PR #18 | Gate upload page behind Google OAuth |
| 2026-03-06 | deploy | Deployed geocoding fix to production |
| 2026-03-05 | infra | Added MAPBOX_ACCESS_TOKEN env var |
```

**Types:** `PR #N`, `deploy`, `infra`, `fix`, `feat`, `refactor`, `docs`

### Rules
- Keep entries to 1-2 lines. This is a log, not a blog.
- Describe the *purpose* of the change, not just the mechanics.
- Never include secrets, credentials, or `.env` contents.
- Include the entry in the same commit as the work it describes.

### Archival
When `progress.md` exceeds 100 entries, move everything except the most recent 50 to `progress-archive.md`. The archive is committed and searchable but not read on session startup.

### If `progress.md` doesn't exist yet
Create it from the template at `agentGuidance/templates/progress.md`. Seed it with recent git history (`git log --oneline -20`) and any known PRs.
