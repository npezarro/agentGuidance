<!-- Load when: pre-deploy and post-deploy checklists -->
# Deployment

## Skill Routing (check before any ad-hoc ssh + pm2)

A 2026-07-01 transcript audit found 97 sessions doing raw `ssh + pm2 restart` deploys with zero skill usage, while the deploy skills sat unused. Before running any ad-hoc deploy or restart command, route through the right skill:

- **shopper, foodie, finance-tracker, travel-assistant, employ** (Next.js subpath apps): `staging` skill. Always.
- **Any other PM2 service on the VM** (bots, APIs, workers): `deploy` skill.
- **"Styling is broken" / unstyled page / dead buttons / `_next/static` 500s** on any production Next.js app: `fix-static-asset-drift` skill; do not debug CSS first.
- **VM feels slow / disk warnings**: `vm-health`, then `vm-cleanup`.

Invoke the skill (Skill tool), don't just Read its SKILL.md — invocation is what loads the full procedure and logs usage.

**shopper, finance-tracker, and travel-assistant always deploy through staging.** Use the `/staging` skill. Do not deploy these apps directly to production unless the user explicitly requests it (e.g., emergency hotfix).

The staging workflow: provision ephemeral staging -> build -> 7 smoke tests -> promote tested artifacts to production -> tear down. See `~/.claude/skills/staging/SKILL.md` for the full procedure.

## Pre-Deploy Checklist

1. All changes committed and pushed via PR.
2. Build succeeds locally.
3. Tests pass.
4. `context.md` updated with deployment intent.
5. No secrets exposed in repository history.
6. Dependencies are locked (`package-lock.json` committed).
7. **If `package.json` or `package-lock.json` changed, run `npm install` on the target before restarting.** Missing this causes crash loops from missing modules.

## Deploy After Every Change to a Deployed App

If you commit changes to a repo that has a live deployment, **deploy immediately**. Do not accumulate commits without deploying. Stale builds are the #1 cause of "page couldn't load" errors in Next.js standalone apps: the HTML references JS chunk IDs from a build that no longer matches the server code or static assets.

This applies especially when:
- Prisma schema or migrations change (the generated client in the standalone build becomes stale)
- Any client component or page changes (static chunk hashes change per build)
- Dependencies are added or updated

If you intentionally skip deploying (e.g., batching changes), note it in context.md so the next session knows a deploy is pending.

## Post-Deploy Verification

"It built clean" is not "it works." Run these within 30 seconds of every deploy:

1. `pm2 show <process>` to confirm status is `online`, uptime is climbing, restart count hasn't spiked.
2. `curl -s -o /dev/null -w "%{http_code}" <url>` to confirm HTTP 200 from the live URL.
3. `pm2 logs <process> --lines 20` to scan for errors, uncaught exceptions, or crash loops in the first 30 seconds.
4. If the app has authentication, verify the sign-in flow works end-to-end.
5. **Test the actual user-facing behavior yourself** before asking the user to verify. Use the browser agent for interactive pages, `curl` for APIs, or direct tool invocation. Never declare "done, try it out" without verifying it works.
   - For Next.js apps: curl a real page (not just the health endpoint) and check for the error boundary pattern (`This page could not be found` or `couldn't load`). The health API can return 200 while every page is broken due to stale chunks.
6. Update `context.md` with deployment status and any issues observed.
7. If any check fails, **do not move on**. Diagnose and fix before declaring the deploy complete.

Infer deploy commands from repo config (GitHub Actions, scripts, `context.md`).

## Automated Deploy Enforcement (Hooks)

Two hooks mechanically enforce post-deploy verification, even if the agent skips the manual checklist above:

1. **`hooks/track-deploy.sh`** (PostToolUse on Bash): Detects `pm2 restart/start/reload` commands and records the deployed service name to a per-session tracker file. Also detects SSH deploy patterns (`ssh ... pm2 restart`). Uses `privateContext/deploy-registry.json` to map PM2 names to services.

2. **`hooks/verify-deploy.sh`** (Stop hook): When a session ends, reads the tracker and curls each deployed service's health endpoint and user-facing URLs from the registry. **Blocks the session exit** if any check fails, forcing the agent to diagnose and fix before stopping.

**Why this exists:** The #1 failure mode was agents deploying, declaring "done," and leaving without testing. The Stop hook makes this structurally impossible for registered services.

3. **`hooks/check-commit-deploy.sh`** (Stop hook): Detects when files were modified in a repo that has a live deployment (per `deploy-registry.json` `repo` field) but no deploy was performed during the session. **Blocks the session exit** until the agent either deploys or documents the pending deploy in context.md.

**Why this exists:** The #2 failure mode was agents committing code to deployed repos and ending the session without deploying. The committed code sat stale while production served the old build (employ incident, 2026-06-29).

## Next.js Standalone Symlink Fix

When using `output: 'standalone'` in `next.config`, Next.js produces a minimal server in `.next/standalone/` but does NOT include the `static/` or `public/` directories. Without symlinks, all CSS, JS, and static assets return 404.

Add a `postbuild` script to `package.json`:

```json
"postbuild": "bash -c 'STANDALONE=.next/standalone; [ -d \"$STANDALONE\" ] && { rm -rf $STANDALONE/.next/static && ln -sf ../../../.next/static $STANDALONE/.next/static; [ -d public ] && rm -rf $STANDALONE/public && ln -sf ../../public $STANDALONE/public; echo \"[postbuild] standalone symlinks created\"; } || true'"
```

npm runs `postbuild` automatically after `build`. This pattern is used in finance-tracker.

**Note:** netflix-social was previously on this list but switched to `output: 'export'` (GitHub Pages static export) in May 2026. Do not copy the standalone symlink pattern from netflix-social — it no longer uses it.

## Next.js 16: Also Copy `.next/server` to Standalone

**Next.js 16 bug:** Standalone builds omit `.next/server/` (app-router server files). Copying only `.next/static` and `public/` is not enough — omitting `.next/server` causes `InvariantError: client reference manifest does not exist` on any route with `use client` components or app-router pages.

**Fix:** In your build script, copy both `.next/static` **and** `.next/server` into the standalone output:

```bash
STANDALONE=.next/standalone
cp -r .next/static  $STANDALONE/.next/static
cp -r .next/server  $STANDALONE/.next/server
cp -r public        $STANDALONE/public
```

**Detection:** The error manifests at runtime, not at build time — the app starts fine (`pm2` shows `online`, `/api/health` returns 200) but any app-router page with client components throws `InvariantError: client reference manifest for route "/X" does not exist`.

Source: runEvaluator commit `6f78038` (2026-06-01), run #647.

## GitHub Pages Static Export (No-Server Alternative)

For apps that don't require SSR, auth, or server-side API routes, `output: 'export'` produces a static site that can be hosted on GitHub Pages for free — no VM, no PM2, no Apache config needed.

```ts
const nextConfig: NextConfig = {
  basePath: "/repo-name",   // must match GitHub Pages subpath
  output: "export",
  images: { unoptimized: true },  // required — no Image Optimization API
};
```

**When to use GitHub Pages over VM PM2:**
- Pure demo/portfolio/static-content apps
- No server-side API routes, database, or OAuth
- No need for Apache ProxyPass config
- App is public (no auth gate needed)

**When to stay on VM PM2:**
- Needs dynamic API routes, SQLite, or server-side rendering
- Needs Google OAuth or any server-side auth
- Needs a Docker bridge or external service integration
- Needs Discord notifications, webhooks, or cron jobs

**Deploy pattern:** Build locally → commit `out/` or let GitHub Actions build → GitHub Pages serves from the branch. Source: netflix-social (commit 928a1d7, 2026-05).

## Next.js Standalone: Missing Packages (`serverExternalPackages`)

When using `output: 'standalone'`, Next.js traces imports at build time but doesn't always capture server-only packages invoked indirectly (inside `.then()` handlers, dynamic requires, email libraries). Missing packages cause `MODULE_NOT_FOUND` at runtime.

**Fix:** Add untraced packages to `serverExternalPackages` in `next.config.ts`:
```ts
const nextConfig: NextConfig = {
  output: 'standalone',
  serverExternalPackages: ['nodemailer'],
};
```

Also wrap non-critical side effects (e.g., `sendEmail()`) in `try/catch` so they can't fail the main operation.

**Packages commonly missing:** `nodemailer`, packages using native bindings, packages only imported in server action callbacks. Source: shopper standalone build (2026-05-15).

## Next.js Standalone: Adaptive `start.sh` Must Guard the Flat Branch on `node_modules/next`

Several apps (shopper/foodie/travel-assistant/employ family) use a `start.sh` that auto-detects layout so the same script works in both a flat prod deploy (`server.js` at the app root) and a standalone dev/staging build (`.next/standalone/server.js`). If the flat-branch check only tests `[ -f "./server.js" ] && [ -d "./.next/server" ]`, it can pick the flat layout on a tree that has those two paths but **no root `node_modules`** (e.g. a fresh git clone used for staging, or a partial rsync artifact) — PM2 then crash-loops on `Error: Cannot find module 'next'` (`MODULE_NOT_FOUND`, requireStack pointing at the root `server.js`).

**Fix:** require `[ -d "./node_modules/next" ]` as part of the flat-branch condition, so an incomplete tree falls through to `.next/standalone/server.js` (which carries its own traced `node_modules`) instead of crash-looping:
```bash
if [ -f "./server.js" ] && [ -d "./.next/server" ] && [ -d "./node_modules/next" ]; then
  STANDALONE_DIR="."
elif [ -f "./.next/standalone/server.js" ]; then
  STANDALONE_DIR="./.next/standalone"
else
  echo "Critical: server.js not found in . or ./.next/standalone." >&2
  exit 1
fi
```

Source: employ `f7901a0` (2026-07-17) — this exact crash-loop hit `staging-employ`. **Confirmed still unguarded in shopper's `start.sh` as of 2026-07-17** (identical `[ -f "./server.js" ] && [ -d "./.next/server" ]` check, no `node_modules/next` guard) — a live latent risk for any future shopper staging deploy that clones fresh or does a partial rsync; travel-assistant and foodie were checked and don't use this flat/standalone branch at all (they always resolve `.next/standalone/server.js` directly), so they're not affected. Audit any new app cloned from this scaffold for the same gap before it bites in staging.

## Next.js Standalone: Relative SQLite Paths Break

When using `output: 'standalone'`, `process.cwd()` inside `.next/standalone/server.js` resolves to the `.next/standalone/` directory, not the project root. Any `DATABASE_URL` using a relative path (e.g. `file:./prisma/dev.db` or `file:./data/production.db`) will open or create the DB inside `.next/standalone/` instead of the intended location.

**Fix:** Add an absolute-path resolver in your Prisma/DB client:
```ts
import path from "path";
let url = process.env.DATABASE_URL || "file:./prisma/dev.db";
if (url.startsWith("file:")) {
  const filePath = url.slice(5);
  if (!path.isAbsolute(filePath)) {
    const isStandalone = process.cwd().includes(path.join(".next", "standalone"));
    const root = isStandalone ? path.join(process.cwd(), "..", "..") : process.cwd();
    url = `file:${path.resolve(root, filePath)}`;
  }
}
```

This pattern is used in `runEvaluator/lib/prisma.ts` and `health-hub/src/lib/db.ts`. The `isStandalone` check ensures dev mode (where `process.cwd()` is the project root) keeps working.

## Python Version Compatibility

The GCP VM runs **Python 3.9**. Modern type annotation syntax (`X | None`, `list[str]`, `dict[str, Any]`) requires Python 3.10+. Code using these features will raise `TypeError` at runtime on the VM.

**Fix:** Add `from __future__ import annotations` at the top of every Python file that uses modern type syntax. This makes all annotations strings (evaluated lazily), avoiding the runtime error on 3.9.

This caused 3 failed PRs on llm-tasks (2026-04-05) before the root cause was identified. Always test Python code against 3.9 syntax rules before deploying to the VM.

## Check the Server Before Asking

When you're missing information about production — env vars, configs, logs, database state, file paths, what's running — SSH into the VM and look it up rather than asking the user. The VM is a live, authoritative source. Check `.env` files, PM2 configs, Apache configs, logs, and file structure. Also check `~/repos/privateContext/` locally for credentials and reference files. See `privateContext/infrastructure.md` for access details.

**Why:** The user treats the VM and local machine as a unified environment. Asking for information that's already discoverable wastes time.

**Don't assume infrastructure.** Never assume Docker, Kubernetes, or any specific container runtime is available. Most services run as bare PM2 processes on the VM. Check `privateContext/infrastructure.md` and `knowledgeBase/infra/vm-overview.md` for the actual service topology before trying container commands.

## Check Infrastructure Before Assuming

When encountering a database connection, service, or dependency that isn't reachable locally, check the actual infrastructure before guessing at local tools:

1. Check `knowledgeBase/infra/` for the service's documented location and architecture
2. Check `privateContext/` for connection details and credentials
3. Try SSH-ing to the VM — most services run on the cloud VM, not locally
4. Only try local tools (Docker, localhost) if the above confirms local deployment

**Why:** A session assumed Docker for a PostgreSQL connection when the DB was on the VM. This system has no Docker installed — the knowledgeBase and privateContext document all services. Wasting time on wrong assumptions is avoidable.

## Apache ProxyPass Trailing-Slash Gotcha

When Apache `ProxyPass` is defined with a trailing slash (e.g., `ProxyPass /app/ http://...`), the bare path `/app` does NOT match. After OIDC auth, the browser returns to the original URL (without slash), causing a 404 as the request falls through to WordPress.

**Fix:** For every `ProxyPass /app/` directive, add a matching redirect:
```apache
RedirectMatch ^/app$ /app/
```

This pattern affected ClaudeNet, Epic Auth, and other services after adding an OIDC-protected project index page (2026-04-28). The `/manchu` route already had this redirect, which is why it worked while others broke.

**When adding a new ProxyPass directive**, always check whether it uses trailing slashes and add the `RedirectMatch` if so.
## .env Protection During rsync Deploys

When using `rsync --delete` to deploy, **always `--exclude '.env'`**. The `--delete` flag removes server-side files not in the source, which will overwrite the production `.env` (with its production-specific values like database ports, API endpoints) with local dev config.

```bash
# GOOD: Exclude .env from rsync
rsync -az --delete --exclude '.env' --exclude 'node_modules' ./dist/ "$DEPLOY_TARGET"

# BAD: rsync --delete with no .env exclusion
rsync -az --delete ./dist/ "$DEPLOY_TARGET"
```

**Post-deploy .env integrity check:** After rsync, verify critical env vars on the server still have production values. A silent overwrite causes hard-to-diagnose failures (e.g., wrong database port, wrong API base URL) that look like application bugs.

**Why this matters:** A real deploy overwrote a production database port with a local dev port, causing all connections to fail silently. The root cause was `rsync --delete` without `--exclude .env`.

## Concurrent Bot Deploys Race Against PM2 — Serialize with flock

**Any PM2-managed Next.js app that receives autonomous bot deploy triggers (fix-checker, Gemini, learning-agent PRs) must wrap its entire build+restart in `flock`.** Without serialization, a second `next build` deletes `.next/standalone/server.js` while PM2 is still running the previous build's process, causing `ERR_MODULE_NOT_FOUND` crash loops that persist until manual recovery.

**Root cause (2026-06-07 runeval outage):** The fix-checker bot opened and auto-merged a Gemini PR while a human operator deploy was in flight. The second `next build` clobbered the standalone artifact at `ERR_MODULE_NOT_FOUND`, PM2 hit max restarts, and the process dropped offline. The failure mode is silent — PM2 logs `max restart limit reached` but doesn't explain why server.js disappeared.

**Fix:** `deploy.sh` must acquire an exclusive file lock before building:

```bash
#!/bin/bash
set -e
LOCK_FILE="/tmp/<app>-deploy.lock"
# Guard against re-entry (flock re-executes the script with the lock held)
if [ "${DEPLOY_LOCK_BYPASS:-0}" != "1" ] && [ -z "${<APP>_DEPLOY_LOCKED:-}" ]; then
    if [ "${DEPLOY_LOCK_WAIT:-1}" = "1" ]; then
        exec env <APP>_DEPLOY_LOCKED=1 flock -x -w 900 "$LOCK_FILE" "$0" "$@"
    else
        exec env <APP>_DEPLOY_LOCKED=1 flock -x -n "$LOCK_FILE" "$0" "$@"
    fi
fi
# ... git hard-reset to origin/main, npm run build, pm2 restart, health check
```

**CLAUDE.md rule:** Add a line mandating `./deploy.sh` over bare `npm run build && pm2 restart`. Without this, agents and operators bypass the lock.

**Repos with this pattern:** runeval (`deploy.sh` commit `810573e` + `23e8036`), health-hub (`deploy.sh` commit `4a031fe`). Apply to any Next.js standalone app whose fix-checker is active.

**Env knobs:** `DEPLOY_LOCK_WAIT=0` to fail fast, `DEPLOY_LOCK_BYPASS=1` as a break-glass escape hatch (coordinate before using).

## Stop PM2 Before Next.js Standalone Builds

`next build` deletes `.next/standalone/server.js` before recreating it. If PM2 is running and the process restarts (for any reason) during this window, PM2 crash-loops on `MODULE_NOT_FOUND` until the build finishes. With `max_restarts: 10` or higher, this can burn through all restart attempts before the build completes, leaving the process errored.

**Fix:** Always stop PM2 before building a standalone Next.js app:
```bash
pm2 stop <process>; npm run build && pm2 restart <process> --update-env
```

Use `;` (not `&&`) after `pm2 stop` so the build proceeds even if the process was already stopped or doesn't exist yet (first deploy).

**Why:** runeval observed 27+ PM2 restart attempts during a single build window (2026-06-03). The build completed successfully but PM2 had already entered "errored" state.

This is a simpler, narrower complement to the `flock` serialization above — it's about a single deploy's own build-vs-serve race, not concurrent deploys stepping on each other. Apply both where relevant.

## Concurrent rsyncs Silently Drop Subdirectories

**Never run parallel rsyncs from the same dev host to multiple production directories.** Concurrent rsync operations (e.g., deploying shopper, foodie, and travel in the same shell session with `&`) can silently drop subdirectories in the destination.

**Observed failure (2026-05-29):** Three apps deployed in parallel via rsync. One app's `.next/standalone/.next/server/chunks/ssr/` directory was silently missing. PM2 showed the process as `online` and `/api/health` returned 200 (health checks don't render SSR routes). The failure only surfaced when a user navigated to an app-router page: `InvariantError: client reference manifest for route "/search" does not exist`.

**Rule:** When batch-deploying multiple apps with rsync artifacts, **run rsyncs sequentially**. After each rsync, verify the artifact tree is complete before restarting PM2:

```bash
# Verify SSR chunks before PM2 restart (Next.js standalone builds)
ls <prod_dir>/.next/standalone/.next/server/chunks/ssr/ \
  || { echo "SSR chunks missing — re-run rsync before restarting PM2"; exit 1; }
```

**Why it's hard to catch:** The process appears healthy at the PM2 and health-endpoint level. The root cause (missing ssr/ chunks) is only observable by listing the artifact tree or by exercising an app-router route end-to-end.

## PM2 + ESM Module Incompatibility

**PM2 cluster mode is incompatible with ESM modules.** When a Node.js service uses `"type": "module"` in `package.json` or imports `.mjs` files, setting `exec_mode: "cluster"` in the PM2 ecosystem config will crash the process on start.

**Fix:** Use a `start.sh` bash wrapper and `exec_mode: "fork"`:

```bash
# start.sh
#!/bin/bash
cd /var/www/<service>
source .env 2>/dev/null || true
exec node server.js
```

```js
// ecosystem.config.cjs
{
  script: "./start.sh",
  interpreter: "bash",
  exec_mode: "fork",  // NOT cluster
}
```

Benefits: `start.sh` also loads `.env` before the process starts, ensuring env vars are available at cold start without relying on PM2's env injection (which can miss vars in some setups).

Repos using this pattern: `claude-auto-merger`, `shopper`.

## VM SSH Access

The GCP VM username is **not** the same as the local username. Before SSH-ing or writing paths that reference the home directory, check `privateContext/sensitive-identifiers.md` for the correct username — hardcoding the wrong one is a recurring source of deploy failures. Always use `$HOME` or `~` in scripts rather than hardcoded paths like `/home/<user>/`.

**SSH aliases in automated processes:** SSH config aliases (from `~/.ssh/config`) work in interactive shells but can fail in PM2-managed processes or `execFile`/`spawn` calls. Two independent incidents (claude-auto-merger, fix-checker) hit this: the alias resolved in manual testing but failed when invoked from a Node.js server under PM2. **Fix:** Use `localhost` (when on the VM itself) or the direct IP address in automated scripts. Reserve SSH aliases for interactive/manual use only.

## PM2 Process Lifecycle Timeouts

When configuring PM2 services, set `kill_timeout` and `listen_timeout` in `ecosystem.config.js` for Node.js apps that do async cleanup or take time to bind to a port.

```js
{
  name: 'my-service',
  script: 'server.js',
  kill_timeout: 10000,    // ms to wait for graceful shutdown before SIGKILL (default: 1600)
  listen_timeout: 10000,  // ms to wait for app to bind its port before marking crashed (default: 3000)
}
```

**`kill_timeout`:** PM2 sends SIGTERM, then force-kills with SIGKILL after `kill_timeout` ms. Default 1600ms is too short for Next.js apps closing DB connections or finishing in-flight requests. Use **10000ms (10s)** for Next.js standalone apps — experience shows 3000ms can still cause partial shutdown under load, leaving DB connections open and causing the next start to hit connection limit immediately. **Finance-tracker crash loop (2026-05-15):** default kill_timeout caused this. **runeval crash loop (2026-06-02, commit `0ac95bc`):** even 3000ms was insufficient; raised to 10000ms to fully resolve.

**`listen_timeout`:** How long PM2 waits for the app to become "ready" (emit `ready` signal or bind port). If your app takes longer to start than this value, PM2 marks it as crashed before it even starts serving. For Next.js standalone builds, use 10000ms to match `kill_timeout` and give heavy initializers (Prisma, migrations, PRAGMA setup) enough runway.

**`max_memory_restart`:** Remove this from production PM2 configs for Next.js apps. It can trigger unexpected restarts during traffic spikes and is harder to tune than a VM-level OOM guard. Set a Node.js heap cap via `node_args: '--max-old-space-size=1024'` instead and let the OS OOM killer be the last resort.

**Why this matters:** Not setting these explicitly causes intermittent restart storms that look like application bugs but are actually PM2 race conditions during shutdown/startup.

## Prisma + SQLite: WAL Mode Must Be Applied via PRAGMA, Not URL

When using Prisma with SQLite, WAL mode (`journal_mode=WAL`) cannot be set as a query parameter in the `DATABASE_URL`. Prisma's engine does not support it as a URL param and will silently ignore or error on it.

**Correct approach:** Apply WAL mode via `$queryRawUnsafe` after connecting:

```ts
await prisma.$queryRawUnsafe(`PRAGMA journal_mode=WAL;`);
await prisma.$queryRawUnsafe(`PRAGMA busy_timeout=30000;`);
```

If `journal_mode=WAL` appears in `DATABASE_URL` (e.g., from an old deploy.sh), **strip it before passing to Prisma** — do not let it through as a connection parameter.

**URL params that ARE supported:** `connection_limit=1`, `pool_timeout=10`, `busy_timeout=30000`. These prevent "database is locked" errors under concurrent Prisma access.

**Pattern used in:** runeval `lib/prisma.ts` (commit `0ac95bc`, 2026-06-02) — strips `journal_mode` from URL with `url.searchParams.delete("journal_mode")` before constructing the Prisma datasource URL, then applies WAL via PRAGMA at connection time.

## SQLite/DB path must never resolve inside the build tree (silent data loss)

**Incident 2026-06-17 (shopper/foodie/travel/runeval):** Next.js standalone apps run with `cwd = .next/standalone/`. A DB layer that falls back to a RELATIVE path (`process.env.DB_PATH || path.join(process.cwd(), "app.db")`, or Prisma `DATABASE_URL="file:./data/x.db"`) silently creates the live DB INSIDE `.next/` whenever the launch doesn't export an absolute path. `npm run build` does `rm -rf .next`, so every deploy ERASES the DB and all rows written since the last build — silent, intermittent, undetected.

**Rules:**
- Pin an ABSOLUTE DB path in `.env` AND `start.sh`, outside `.next/`. For Prisma use an absolute `file:/abs/path.db` URL.
- Add a boot guard in the DB layer: `if (path.resolve(dbPath).split(path.sep).includes(".next")) throw` — turns silent loss into a loud crash. No-op when configured correctly.
- Add row-count-drop + missing-backup alerting. A corruption/integrity check does NOT catch a DB that is intact but missing rows (no baseline). See VM `~/bin/db-guardian.sh`.

**Deploy-model divergence (don't mix them up):**
- Some VM app dirs are NON-GIT, artifact-only (`.next`+`node_modules`+`package.json`) — deploy via /staging artifact promotion (rsync `.next`), sync loose scripts via scp.
- Others are git repos whose `start.sh` REBUILDS IN-PLACE when the build-manifest `appDir` != prod dir — deploy via `git pull` + in-place build. Artifact-rsync promotion bakes the staging path into `appDir` and triggers an unwanted on-prod rebuild (caused a ~90s outage). Check which model an app uses before deploying.

**Promoting a LOCAL BUILD to an in-place-rebuild prod dir (foodie, travel-assistant):** the `start.sh` reads `.next/required-server-files.json` and compares `appDir` to the prod dir. A WSL-built `.next` records the local dev path (`/home/npezarro/repos/<app>`), which mismatches the prod path, setting `NEEDS_BUILD=1`. Critical step order:
1. `pm2 stop <app>` FIRST — a running `pm2 restart` hits the mismatch on every restart and loops rebuild attempts indefinitely (pm2 re-triggers start.sh each crash).
2. Kill any in-flight rebuild: `pkill -9 -f "next build"` (killing the build can drop the SSH session — reconnect and continue).
3. rsync the clean local `.next/` to both prod `.next/` paths.
4. Patch `appDir` in `.next/required-server-files.json` AND `.next/standalone/.next/required-server-files.json` to the prod path.
5. `pm2 restart <app>` and verify no rebuild fires: `ps -eo pid,cmd | grep "next build"` should be empty.

Full incident: privateContext/deliverables/incidents/2026-06-17-shopper-family-db-data-loss.md

## VM SSH: don't trip fail2ban with reconnect bursts

**Incident 2026-06-30 (a PM2 service deploy):** A burst of short SSH connections to the production VM, plus one deploy SSH killed mid-run and immediately retried, tripped the VM's fail2ban jail on port 22. Result: a ~10-minute DROP ban on the source IP. Roughly 5 rapid or aborted connections are enough.

**The tell (so you diagnose it in seconds, not minutes):**
- SSH connect **times out** (not "connection refused") and ICMP/ping is blocked.
- The production site still returns **HTTP 200 via the CDN**, so the box and web tier are fine; only your SSH is banned.
- Direct-to-origin ports 80/443 are *always* firewalled to CDN-only, so the **only new signal is port 22 timing out** while HTTP works.

**Recovery:** stop all SSH attempts (each retry re-arms/extends the ban), wait 10-12 minutes, then make ONE clean connection.

**Prevention:**
- Run all deploy steps inside a **single SSH invocation** with a generous timeout (180s+), not a sequence of short separate connections.
- Avoid a trailing `pm2 jlist | python ...` parse that can hang the session near the timeout boundary and tempt a kill-and-retry loop. If you need status, give the whole command room (timeout 180s) or split status into a later, separate single connection.

## Apache 60s Proxy Timeout — 202 Async Split Pattern

Apache's default `ProxyTimeout` is 60 seconds. Any Next.js API route that calls a slow backend (LLM, external API, heavy compute) and blocks until completion will hit this limit and return a 502 to the browser.

**Pattern:** Split the long-running request into two parts:
1. **POST → 202 Accepted:** Kick off the work in a detached background task (fire-and-forget promise, PM2 cron, etc.). Return `{ status: "accepted" }` immediately.
2. **GET → status + result:** The client polls this endpoint until the result appears (e.g., a new `generatedAt` timestamp or `generating: false`).

```typescript
// In the API route
const inFlight = new Set<string>();  // module-scoped dedup

export async function POST(req: NextRequest) {
  if (inFlight.has(userId)) return NextResponse.json({ status: "already_running" }, { status: 202 });
  inFlight.add(userId);
  // Fire and forget — don't await
  doSlowWork(userId).finally(() => inFlight.delete(userId));
  return NextResponse.json({ status: "accepted" }, { status: 202 });
}

export async function GET(req: NextRequest) {
  const result = await db.getResult(userId);
  return NextResponse.json({ ...result, generating: inFlight.has(userId) });
}
```

**Client polling (React):**
```typescript
// Poll GET every 4s for up to 4 minutes after triggering POST
useEffect(() => {
  if (!generating) return;
  const id = setInterval(async () => {
    const data = await fetchPlan();
    if (data.generatedAt > lastGenerated) { clearInterval(id); refresh(); }
  }, 4000);
  const timeout = setTimeout(() => clearInterval(id), 240_000);
  return () => { clearInterval(id); clearTimeout(timeout); };
}, [generating]);
```

**Where this matters:** Any Apache-proxied route doing LLM calls (Claude Opus ~30-60s), batch processing, or external API calls >30s. First observed in runeval's training plan generation (commit `21d69a5`, 2026-06-03).

**Alternative for internal cron endpoints:** Curl directly to `http://127.0.0.1:<port>/api/...` (bypasses Apache entirely). Used by PM2 cron processes that don't need timeout workarounds.

## Deploy Scripts Must Hard-Lock to origin/main

**Problem:** Autonomous fix-checker bots (Gemini, Claude learning-agent) create PR branches and can leave the VM's working copy checked out on a bot branch. A naive `git pull origin $(git branch --show-current)` in a deploy script will then silently ship an unreviewed bot branch to production.

**Observed (runeval, 2026-06-03):** `deploy.sh` was pulling the current branch. A Gemini fix-checker left the VM checked out on `gemini/fix-runeval-0603-2053`. The next `./deploy.sh` shipped that in-progress branch to prod, reverting the Plan nav link and losing `TrainingPlan` rows (the bot's schema migration hadn't merged yet).

**Fix pattern** for any deploy script on a repo with autonomous bot activity:
```bash
git fetch origin main
git checkout main
git reset --hard origin/main
# Abort if working tree is dirty rather than silently wiping it
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Working tree dirty — aborting to avoid losing changes."
    git status -sb
    exit 1
fi
```

**Why `reset --hard` over `pull`:** `git pull` with a dirty tree merges or errors. A detached/stale branch silently pulls the wrong history. `reset --hard origin/main` is unambiguous: always lands on exactly what's on the remote main branch.

**Safety:** Abort if the tree is dirty so you don't silently wipe in-progress changes. A dirty tree on a deploy server is a signal something is wrong — investigate, don't bulldoze.

## Cloudflare `CF-IPCountry` Header for Visitor Country Detection (2026-07-18)

When an app is behind Cloudflare (all production apps on this host are), Cloudflare stamps a `CF-IPCountry` header on every origin request with the visitor's ISO 3166-1 alpha-2 country code (e.g. `CA`, `GB`, `DE`). No API call or geo-IP library is needed — the header is free and always present.

**How to read it in a Next.js Server Component or Route Handler:**
```typescript
import { headers } from 'next/headers';

const headersList = await headers();
const rawCountry = headersList.get('CF-IPCountry') ?? '';
// Validate: Cloudflare sends 'XX' for unknown and 'T1' for Tor exit nodes
const countryCode = rawCountry.toUpperCase();
const isReal = /^[A-Z]{2}$/.test(countryCode) && countryCode !== 'XX' && countryCode !== 'T1';
const detectedCountry = isReal ? countryCode.toLowerCase() : 'us'; // fall back to US default
```

**Key caveats:**
- `XX` means Cloudflare couldn't determine the country (unusual traffic, misconfigured IP). Always fall back.
- `T1` means Tor exit node. Always fall back.
- A missing/empty header should also fall back — it won't happen in production behind Cloudflare, but it will during local development (`npm run dev`) where the header is absent.
- **Reading `headers()` makes the Next.js route dynamic.** If the page was previously statically rendered, adding this call opts it out of static pre-rendering. For apps that already use auth or SQLite reads this is harmless (the page is already dynamic).

**When to use:** Geo-aware defaults (e.g., default currency, region picker, shipping-address autocomplete), A/B testing by country, locale-based routing. Use the header value as a default suggestion — always let the user override and persist their choice in `localStorage`.

**Verified 2026-07-18:** shopper's "Shopping from?" combobox defaults to the CF-IPCountry-detected country and overrides with a persisted `localStorage` value. Applies to any app on this Cloudflare-proxied host.

### rsync --chmod=D755,F644 for web-root deploys (mktemp staging perms trap) (2026-07-17)
See memory infra_rsync_mktemp_perms: rsync -a from a mktemp -d staging dir propagates mode 700 onto the destination dir; Apache 403s everything beneath. Always rsync -a --chmod=D755,F644 when deploying to a web root.

### Pin Prisma binaryTargets to the deploy runtime's OpenSSL; never ship a build from a different-OpenSSL host to the VM (2026-07-19)
A Next.js standalone + Prisma app on the production VM (Node links OpenSSL 1.1.1w = debian-openssl-1.1.x) went totally DB-dark on 2026-07-18/19: every DB route/cron returned HTTP 500 with an EMPTY body, homepage still 200'd (static shell) so uptime checks missed it. Cause: prisma/schema.prisma had no binaryTargets, so prisma generate emitted only the build host's engine. A build produced on the WSL dev clone (OpenSSL 3.0.13 = debian-openssl-3.0.x) was shipped out-of-band to the VM, bundling only libquery_engine-debian-openssl-3.0.x into .next/standalone/node_modules/.prisma/client. VM runtime needs 1.1.x -> PrismaClientInitializationError: could not locate the Query Engine. Diagnosis tell-tales: the error's 'searched locations' list names the build-host dev path (/home/npezarro/repos/...); the live-dir reflog head is 'pull: Fast-forward' not deploy.sh's 'reset --hard origin/main' (out-of-band build, same delivery anti-pattern as the static-asset 'styling broke' outage but it breaks the DB layer instead of CSS). Fix (both): (1) pin binaryTargets = [native, debian-openssl-1.1.x, debian-openssl-3.0.x] in schema.prisma so any build host bundles the VM's engine; (2) redeploy via the app's ./deploy.sh, which runs prisma generate ON the VM (native = 1.1.x) and rebuilds standalone with both engines. Verify: a DB-touching endpoint returns 200 and ls .next/standalone/node_modules/.prisma/client shows the 1.1.x engine.

### Apache force-lowercase redirect breaks any SPA with mixed-case asset hashes (2026-06-23)
The production Apache vhost has a global rewrite rule that 301-redirects any URL containing uppercase letters to its lowercase form (`RewriteMap lc int:tolower` + `RewriteRule ^(.*)$ ${lc:$1} [R=301,L]`). **Symptom:** A newly deployed SPA returns 200 for the page HTML but silently breaks every JS/CSS asset that has a mixed-case content hash in its filename (e.g. Vite emits `index-BqcsSXEO.js`). Each asset 301s to its lowercased form, which 404s — the app never boots. Next.js `/_next/static/` hashes are lowercase, so Next.js apps on this host are not affected; Vite-based SPAs are. **Fix:** Add a `RewriteCond %{REQUEST_URI} !^/<your-subpath>` before the global lowercase rule for each new Vite SPA you deploy. **Cloudflare caches the stale 301** at ~4h (max-age 14400); the CDN token lacks Cache-Purge scope, so either wait 4h or force new asset names by rebuilding with a cache-buster. Diagnosed 2026-06-23; documented in `knowledgeBase/infra/vm-deployment-playbook.md`.
