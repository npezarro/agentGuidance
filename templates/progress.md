# Progress Log

> Continuously updated log of all work done on this project. Add entries in reverse chronological order (newest first). One entry per PR, deploy, or significant change. Keep entries concise — 1-2 lines max.
>
> **Update rules:**
> - Add an entry for every merged PR or significant commit
> - Add an entry for every deploy
> - Log infrastructure changes (env vars, server config, deps)
> - Never include secrets, credentials, or .env contents
> - Format: `YYYY-MM-DD | <type> | <description>`
> - When this file exceeds 100 entries, move all but the most recent 50 to `progress-archive.md`

## Log

| Date | Type | Description |
|------|------|-------------|
| YYYY-MM-DD | PR #N | Brief description of what the PR did |
| YYYY-MM-DD | deploy | Deployed to production — what changed |
| YYYY-MM-DD | infra | Changed server config / added env var / updated deps |
| YYYY-MM-DD | fix | Hotfix description |
| YYYY-MM-DD | feat | New feature description |

---

## Examples

Below are example log sections from different project types. Use them as reference for tone, length, and variety.

---

### Example 1: Discord Bot — Active Development

Shows a mix of features, fixes, deploys, and documentation entries over a week of development.

```markdown
| Date | Type | Description |
|------|------|-------------|
| 2026-03-10 | feat | Wire metrics instrumentation, backup cron, and thread auto-archiving — closes three open work items |
| 2026-03-10 | feat | Merged attachment reading, stream-json live logs, and kill false-positive fixes (PRs #14-16 consolidated) |
| 2026-03-08 | fix | Eliminate output-size job kills — incremental text extraction, only memory/timeout can kill. Result capped at 500KB on delivery. |
| 2026-03-08 | fix | Job kill false positives — per-reason kill tracking, removed misleading "likely memory pressure" label |
| 2026-03-08 | fix | Stream-json output + heartbeat — progress threads now show live tool activities and text output |
| 2026-03-07 | feat | Multi-agent debates now default for all requests — agents discuss before implementation |
| 2026-03-07 | feat | Added centralized activity channel — all persona/debate activity crossposted |
| 2026-03-07 | PR #9 | Multi-agent debate system with live cross-channel discussion |
| 2026-03-07 | PR #8 | Fix: prevent cascading SIGINT restart loops and protect running jobs |
| 2026-03-07 | PR #7 | Verbose progress logging + process manager treekill fix |
| 2026-03-06 | PR #5 | Agent personas, job queue, persistence, and stability |
| 2026-03-06 | PR #4 | Fix memory crashes during concurrent jobs |
| 2026-03-04 | PR #1 | Scaffold bot and webhook infrastructure |
| 2026-03-04 | deploy | Initial bot deployment to process manager |
```

**What makes this good:**
- Each entry is 1 line, describing *what* and sometimes *why*
- PR entries reference the PR number for traceability
- Fix entries explain the root cause, not just the symptom
- Deploy entries note what changed

---

### Example 2: Guidance/Documentation Repo — Slow-Burn Maintenance

Shows a docs-heavy repo with PRs, refactors, and occasional features.

```markdown
| Date | Type | Description |
|------|------|-------------|
| 2026-03-07 | feat | Add three guidance files (session-lifecycle, resource-awareness, process-hygiene) distilled from bot development |
| 2026-03-07 | docs | Elevate progress.md to mandatory core instruction — every commit requires an entry |
| 2026-03-07 | refactor | Extract platform-specific details from agent.md to dedicated repo, add progress.md system |
| 2026-03-05 | PR #11 | Add public repo warning — duplicate PR merged |
| 2026-03-04 | PR #10 | Add public repo warning and expand Security section |
| 2026-03-04 | PR #7 | Expand integration docs for full agent-server interaction |
| 2026-03-04 | PR #2 | Add regression and functional verification to testing rules |
| 2026-03-01 | PR #1 | Comprehensive guidance improvements with modular sub-guidance and templates |
```

**What makes this good:**
- `docs` type used for documentation-only changes
- `refactor` type used when moving code/content without changing behavior
- Entries are concise but still explain the *impact* of the change

---

### Example 3: CLI Tool — Early Stage

Shows a project in its first days with just a few entries.

```markdown
| Date | Type | Description |
|------|------|-------------|
| 2026-03-08 | feat | Initial build — CLI with check-links, scrape, discover, enrich, full pipeline commands. Fetch-based adapters for 3 ATS platforms. 20 companies configured. |
```

**What makes this good:**
- Even a single entry captures the full scope of what was built
- Lists the major components so the next agent knows what exists
- "20 companies configured" gives a sense of scale without listing them all
