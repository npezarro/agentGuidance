# Deployment

## Staging-First Apps

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

## Next.js Standalone Symlink Fix

When using `output: 'standalone'` in `next.config`, Next.js produces a minimal server in `.next/standalone/` but does NOT include the `static/` or `public/` directories. Without symlinks, all CSS, JS, and static assets return 404.

Add a `postbuild` script to `package.json`:

```json
"postbuild": "bash -c 'STANDALONE=.next/standalone; [ -d \"$STANDALONE\" ] && { rm -rf $STANDALONE/.next/static && ln -sf ../../../.next/static $STANDALONE/.next/static; [ -d public ] && rm -rf $STANDALONE/public && ln -sf ../../public $STANDALONE/public; echo \"[postbuild] standalone symlinks created\"; } || true'"
```

npm runs `postbuild` automatically after `build`. This pattern is used in finance-tracker.

**Note:** netflix-social was previously on this list but switched to `output: 'export'` (GitHub Pages static export) in May 2026. Do not copy the standalone symlink pattern from netflix-social — it no longer uses it.

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

## Webhook-Triggered Deploy: Timeout and In-Flight Dedup

When a webhook handler spawns a build process via `execFile`/`child_process.spawn`, two failure modes arise:

**1. Timeout too short for the actual build.** Next.js builds on the VM take 5-10 minutes. A 120s `execFile` timeout SIGTERMs the build mid-type-check, leaving `.next/` gutted (no `standalone/`, no `BUILD_ID`). PM2 keeps serving HTML from open file handles while every static chunk 404s (or worse: Cloudflare caches the 500s under immutable headers). **Fix:** Set `execFile` timeout to at least 900,000ms (15 min) for any build that includes `next build`.

**2. Burst webhook events trigger concurrent builds for the same target.** PR-merged + branch-delete push events arrive within seconds of each other. Without dedup, two builds run in the same directory simultaneously, producing the same gutted-artifact failure mode as the flock section above. **Fix:** Track in-flight deploys in a `Set` keyed by target name; skip (and log) any trigger whose target is already building:

```js
const deploysInFlight = new Set();

async function triggerDeploy(target) {
  if (deploysInFlight.has(target)) {
    log(`deploy for ${target} already running — skipping duplicate trigger`);
    return;
  }
  deploysInFlight.add(target);
  try {
    await execFile('deploy.sh', [target], { timeout: 900_000 });
  } finally {
    deploysInFlight.delete(target);
  }
}
```

**Source:** claude-auto-merger `e98b4a8` (2026-06-12), which hardened the deploy pipeline after a doc-sync PR fired two triggers within 2s and a 120s timeout killed the build mid-type-check.

**Diagnosing stuck Cloudflare-cached 500s after a bad deploy:** If static assets return errors even after a successful re-deploy, Cloudflare may have cached a 500 response under `cache-control: immutable` headers. Diagnose with `curl -sI <asset-url>` — look for `cf-cache-status: HIT` on a 4xx/5xx. Recovery: add a temporary bypass-cache rule for the affected path prefix (see `cloudflare-site-setup` skill for the API commands). The bypass rule forces CF to re-fetch from origin on every request. Remove it once the 500 is no longer live. If your CF API token lacks `Cache Purge:Purge` scope, this bypass-rule workaround is the only programmatic option (dashboard only for adding purge scope). Source: 2026-06-14 runeval incident; documented in `cloudflare-site-setup/SKILL.md`.

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
  kill_timeout: 3000,    // ms to wait for graceful shutdown before SIGKILL (default: 1600)
  listen_timeout: 3000,  // ms to wait for app to bind its port before marking crashed (default: 3000)
  max_memory_restart: '1G',
}
```

**`kill_timeout`:** PM2 sends SIGTERM, then force-kills with SIGKILL after `kill_timeout` ms. Default 1600ms is too short for Next.js apps closing DB connections or finishing in-flight requests. Use 3000ms minimum. **Finance-tracker crash loop (2026-05-15):** default kill_timeout caused partial shutdown, leaving DB connections open, causing the next start to hit connection limit immediately.

**`listen_timeout`:** How long PM2 waits for the app to become "ready" (emit `ready` signal or bind port). If your app takes longer to start than this value, PM2 marks it as crashed before it even starts serving. For Next.js standalone builds, 3000ms is usually sufficient; increase to 5000ms if the app does heavy initialization.

**Why this matters:** Not setting these explicitly causes intermittent restart storms that look like application bugs but are actually PM2 race conditions during shutdown/startup.

## SQLite/DB path must never resolve inside the build tree (silent data loss)

**Incident 2026-06-17 (shopper/foodie/travel/runeval):** Next.js standalone apps run with `cwd = .next/standalone/`. A DB layer that falls back to a RELATIVE path (`process.env.DB_PATH || path.join(process.cwd(), "app.db")`, or Prisma `DATABASE_URL="file:./data/x.db"`) silently creates the live DB INSIDE `.next/` whenever the launch doesn't export an absolute path. `npm run build` does `rm -rf .next`, so every deploy ERASES the DB and all rows written since the last build — silent, intermittent, undetected.

**Rules:**
- Pin an ABSOLUTE DB path in `.env` AND `start.sh`, outside `.next/`. For Prisma use an absolute `file:/abs/path.db` URL.
- Add a boot guard in the DB layer: `if (path.resolve(dbPath).split(path.sep).includes(".next")) throw` — turns silent loss into a loud crash. No-op when configured correctly.
- Add row-count-drop + missing-backup alerting. A corruption/integrity check does NOT catch a DB that is intact but missing rows (no baseline). See VM `~/bin/db-guardian.sh`.

**Deploy-model divergence (don't mix them up):**
- Some VM app dirs are NON-GIT, artifact-only (`.next`+`node_modules`+`package.json`) — deploy via /staging artifact promotion (rsync `.next`), sync loose scripts via scp.
- Others are git repos whose `start.sh` REBUILDS IN-PLACE when the build-manifest `appDir` != prod dir — deploy via `git pull` + in-place build. Artifact-rsync promotion bakes the staging path into `appDir` and triggers an unwanted on-prod rebuild (caused a ~90s outage). Check which model an app uses before deploying.

Full incident: privateContext/deliverables/incidents/2026-06-17-shopper-family-db-data-loss.md

## Next.js Standalone: Flat VM Layout vs Nested Dev Layout in start.sh

When deploying a Next.js standalone build, `rsync` typically copies the **contents** of `.next/standalone/` to the target directory (e.g., `/var/www/app/`). This produces a **flat layout** where `server.js` is at the root:

```
/var/www/app/
  server.js           ← direct (flat deploy)
  .next/
    server/
    ...
```

A dev clone has the **nested layout** where the standalone dir is still under `.next/`:

```
<project>/
  .next/
    standalone/
      server.js       ← nested (local dev)
      .next/
        server/
```

If `start.sh` only checks for `.next/standalone/server.js` (nested), it will not find the file in a flat VM deploy and fall through to `npm run build` — which fails on the VM if the `next` CLI isn't installed, or overwrites a working build unnecessarily.

**Fix — detect layout in start.sh:**
```bash
if [ -f "./server.js" ] && [ -d "./.next/server" ]; then
  # Flat VM deploy: standalone contents rsynced to this dir
  exec node ./server.js
elif [ -f "./.next/standalone/server.js" ]; then
  # Nested dev layout
  exec node ./.next/standalone/server.js
else
  echo "No server.js found in flat or nested location — build may be missing"; exit 1
fi
```

**Why the layout differs:** `rsync -az .next/standalone/ /var/www/app/` (trailing slash on source) copies the directory's contents rather than the directory itself, flattening the path. `rsync -az .next/standalone /var/www/app/` (no trailing slash) would nest it. The flat rsync is the common idiom in deploy scripts here.

Source: employ `start.sh` commit `1d369cc` (2026-06-14) — start.sh was always triggering `npm run build` on the VM because it only checked `.next/standalone/server.js`; flat rsync had placed `server.js` at root.

## Auto-Deploy Wrapper Bootstrap Problem

When you add a `git pull --ff-only` at the top of a cron or automated script to enable self-updating, the **already-deployed copy** on the remote machine does not have that wrapper yet. Since the remote is pinned at the pre-wrapper commit, it cannot self-pull the wrapper and stays stuck indefinitely.

**The trap:** "Fixes will auto-deploy after I push the wrapper" is only true for the NEXT invocation after the wrapper is manually bootstrapped. Until a human runs `git pull` on the remote, the script runs the old version on every cron tick regardless of what you push.

**Arc-prize-2026 incident (2026-06-14 to 06-23):** PC2's overnight runner was pinned at `04f00fa` (an unstable PyTorch config). The auto-pull wrapper and the revert were committed after that pin — so PC2 had no mechanism to receive them. Every overnight run from Jun 14–23 (9 days, 0/60 results each) was wasted. A one-time manual `git pull` on PC2 on 2026-06-23 broke the loop.

**Rule:** When pushing a self-update wrapper to an existing deployed script, immediately follow up with a manual deploy to all remote machines. Add it to your deploy checklist: "verify remote is now running the wrapper version before trusting auto-deploy."

**Corollary:** never claim "future changes will auto-deploy" in handoff docs unless the remote has already received and is running the auto-pull wrapper.

## `npm install --production=false` in VM Build Scripts

When a VM-side deploy script runs `npm install` inside a directory where `NODE_ENV=production` is set (common in PM2 ecosystem configs), npm skips `devDependencies`. Build tooling (`next`, `typescript`, `esbuild`, etc.) lives in devDeps and is absent after a production install — the subsequent `npm run build` fails.

**Fix:** Always pass `--production=false` to npm install in build scripts, regardless of environment:

```bash
# In vm-deploy.sh or similar on-VM build scripts:
npm install --production=false   # always install devDeps — they're needed for the build
npx prisma generate              # if applicable
npm run build
```

**Why the default is wrong here:** `NODE_ENV=production` is correct for the running app but wrong for the install-and-build step. A bare `npm install` in a production environment is a footgun: it silently omits the tools you need, with an error that looks like "next: command not found" rather than "missing devDependency."

Source: finance-tracker `scripts/vm-deploy.sh` commit `a78a06b` (2026-06-14).

## start.sh: Always `cd` to Script Directory First

At the top of every `start.sh`, do `cd "$(dirname "$0")"` before any path operations:

```bash
#!/bin/bash
cd "$(dirname "$0")"  # all subsequent paths are relative to the script's dir
[ -f .env ] && source .env
```

Without this, if PM2 or a cron job invokes `start.sh` from a different working directory, every relative path (`./employ.db`, `./.next/standalone/`, `$(pwd)`) silently resolves to the wrong location. `$(dirname "$0")` is the script's own dir regardless of the caller's `$PWD`. Also use `$(pwd)` (not the capture `CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)`) since after the leading `cd`, `$(pwd)` is already correct.

Source: employ commit `207d378` (2026-06-14).

## Bash Scripts: Use `node -e` for JSON Parsing, Not sed/grep

When a shell script needs to extract a field from a JSON file, use `node -e` instead of `sed`/`grep`:

```bash
# Fragile — breaks on whitespace variations, nested keys, or multiline values
MANIFEST_DIR=$(grep '"appDir":' "$MANIFEST" | sed 's/.*"appDir": "\([^"]*\)".*/\1/')

# Robust — handles any valid JSON, fails cleanly on error
MANIFEST_DIR=$(node -e "try { const m=require('$MANIFEST'); console.log(m.appDir || '') } catch(e) { process.exit(1) }" 2>/dev/null)
```

Check the exit code (`$?`) after the `node -e` call: exit 1 means the file was missing or unparseable. The `try/catch` ensures the process exits cleanly rather than printing a stack trace to stdout that gets captured as the value.

**When to use:** Any bash script that reads a JSON build artifact (`.next/required-server-files.json`, `package.json`, health endpoint response) to make a branching decision. `sed`/`grep` on JSON is fragile and fails silently on minor format differences.

Source: employ commit `207d378` (2026-06-14).
