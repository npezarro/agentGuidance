# context.md

> Copy this template to the root of your project and fill it in.
> Update on the final commit of a branch (before creating a PR) or during Session Wrap-Up. Not needed on every intermediate commit.
> The next agent depends on this document.

## Last Updated
<!-- YYYY-MM-DD — one-line summary of the latest change -->

## Current State
<!-- What works, what's deployed, known issues -->
-

## Open Work
<!-- Blockers, unfinished tasks, decisions needed -->
-

## Environment Notes
<!-- Fill in what applies to this project -->
- **Deploy target:** <!-- e.g., Vercel, VPS, AWS, local only -->
- **SSH user / host:** <!-- e.g., deploy@example.com -->
- **Process manager:** <!-- e.g., PM2 process name -->
- **Port:** <!-- e.g., 3000 -->
- **Web server config:** <!-- e.g., /etc/apache2/sites-available/mysite.conf -->
- **Base path:** <!-- e.g., /app (if deployed to a subdirectory) -->
- **Database:** <!-- e.g., SQLite at ./data/app.db, or PostgreSQL on localhost:5432 -->
- **Node version:** <!-- e.g., 20.x -->

## Active Branch
<!-- Current working branch name -->

---

**Never include:** credentials, API keys, tokens, passwords, or `.env` contents.
**For change history**, see `progress.md`.

---

## Examples

Below are three filled-in examples based on different project types. Use them as reference when writing your own `context.md`.

---

### Example 1: Discord Bot (Node.js, PM2, VPS)

```markdown
# Context — my-discord-bot

Last Updated: 2026-03-10 — Wired metrics instrumentation, added backup cron, thread auto-archiving

## Current State
- Bot is **online** via PM2
- Jobs survive bot restarts: processes are detached, state persisted to `data/jobs.json`
- SIGTERM/SIGINT handlers save state before exit; recovery on startup re-attaches or delivers results
- Multi-agent debate system active: all requests go through debate then synthesis before execution
- 5 specialist agent personas with dedicated channels and auto-routing

## Architecture
src/
  bot/
    index.js          — Client, signal handlers, recovery on startup, message routing
    actions.js         — Autonomous action library (send, create channels/threads, pin)
    claudeReply.js     — Request/reply handlers, detached process spawning, job recovery
    debate.js          — Multi-agent debate orchestrator with fault tolerance
    personas.js        — Agent persona definitions and system prompts
    jobStore.js        — Persistent job/queue state (atomic JSON writes)
    metrics.js         — In-memory metrics logger with periodic persistence
  webhooks/
    send.js            — Standalone webhook sender with retry logic
data/
  jobs.json            — Persisted job state (gitignored, auto-created)
  metrics.json         — Cumulative metrics (gitignored, auto-created)

## Open Work
- API token flagged for rotation — user will replace manually

## Environment Notes
- **Deploy target:** VPS
- **Process manager:** PM2 (`my-bot`)
- **Node version:** 20.x
- **Port:** N/A (bot connects outbound via WebSocket)
- **Database:** JSON file persistence (`data/jobs.json`, `data/metrics.json`)
- `.env` at project root (gitignored)

## Active Branch
`main`
```

---

### Example 2: Full-Stack Web App (Vite + Express, PostgreSQL, Apache reverse proxy)

```markdown
# context.md
Last Updated: 2026-03-06 — Fixed blank page and added geocoding fallback

## Current State
- App is live at example.com/myapp
- Serves correctly with BASE_PATH=/myapp
- Geocoding works via Nominatim (free, no API key) as fallback when Mapbox token is not configured
- Database uses standard pg driver against local PostgreSQL

## Open Work
- MapView component is still a placeholder (no real map library integration)
- JS bundle is ~726KB — could benefit from code splitting
- MemoryStore for sessions should be replaced with connect-pg-simple for production
- Receipt OCR: currently manual entry only

## Environment Notes
- **Deploy target:** VPS via Apache ProxyPass
- **Process manager:** PM2 (`my-web-app`)
- **Port:** 8080 (production), 5000 (dev)
- **Base path:** /myapp (build time for Vite, runtime for Express)
- **Database:** local PostgreSQL via DATABASE_URL
- **Build:** `npm run build:deploy` (sets BASE_PATH, runs Vite + esbuild)
- **Start:** `npm run start` (NODE_ENV=production node dist/index.js)
- **Node version:** 20.x

## Active Branch
claude/fix-blank-page
```

---

### Example 3: CLI Tool (Node.js, no server)

```markdown
# context.md
Last Updated: 2026-03-08 — Initial build of job scraper CLI tool

## Current State
- All CLI commands functional: `check-links`, `scrape`, `discover`, `enrich`, `full`
- Fetch-based adapters working for Greenhouse (JSON API), Ashby (GraphQL), Lever (JSON API)
- Generic adapter for custom career pages (HTML + JSON-LD extraction)
- Browser adapter (Playwright) defined but not yet installed — lazy-loaded on demand
- Discovery tested: found 97 roles across configured companies

## Known Issues
- Some companies returned 404 from their APIs — they may have migrated ATS platforms
- Generic adapter cannot list roles (only scrape individual URLs) — needs Playwright for JS-rendered pages
- Playwright not yet installed — `npx playwright install chromium` needed before using browser adapter

## Open Work
- Install Playwright chromium if browser-rendered career pages are needed
- Consider adding cron job for scheduled discovery runs

## Environment Notes
- **Deploy target:** local only (CLI tool, run-and-exit)
- **Node version:** 20.x
- **Database:** none (reads/writes local files)
- **Cache dir:** `~/.cache/my-scraper/` (planned, not yet used)

## Active Branch
`main`
```
