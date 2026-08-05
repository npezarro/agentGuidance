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
   - For Next.js apps: curl a real page (not just the health endpoint) and check for the error boundary pattern (`couldn't load` or `application error`). The health API can return 200 while every page is broken due to stale chunks. **Do NOT grep for "could not be found"** — Next.js RSC payloads embed the 404 handler template inside `<script>` tags, causing false positives even on healthy pages. Strip script tags first: `curl -sL <url> | sed 's/<script[^>]*>.*<\/script>//g' | grep -qi "couldn't load\|application error"`.
6. Update `context.md` with deployment status and any issues observed.
7. If any check fails, **do not move on**. Diagnose and fix before declaring the deploy complete.

Infer deploy commands from repo config (GitHub Actions, scripts, `context.md`).

## Publishing Artifacts: Verify the Bytes, Not the Status Code

For anything that publishes a downloadable artifact (installers, auto-update manifests, release binaries), a 200/206 proves only that *something* is at the URL. A CDN will happily serve a stale cached object of the right size, so the status check passes while the client's integrity check rejects the download: CI green, user broken.

A publish step ending in `echo "Uploaded v$VERSION"` has asserted success, not measured it. Verify, in order:

1. Fetch the manifest **cache-busted**; assert the published version equals the built one.
2. For **every** artifact URL the manifest advertises (not one representative), `curl -sL` with a range request and assert a *final* 200/206. **Follow redirects** — a 301 to a path that 404s looks like success until you follow it.
3. Download the primary artifact and assert its checksum matches the manifest. This is the same check the client performs, and the only one that catches a poisoned cache.

Publish order matters: **binaries first, manifest last** (the manifest advertises the version, so landing it first lets a client 404 mid-upload), and write the manifest to a temp name then `mv` it. Add retention — nothing pruning releases let one directory reach 2.1GB on a disk at 81%.

Three traps that cost three months of silently-broken releases (2026-07-29, claude-tray-notifier):

- **Never discard the stderr of a command that can abort the script.** `ssh-keyscan ... 2>/dev/null` under `bash -e` killed a step instantly with zero output and no packet reaching the server. Tell: a step failing *far too fast* with an empty log is an aborted `set -e` script, not the failure it appears to be.
- **A CDN-fronted hostname is not an SSH target.** Keep the origin address and the public hostname as separate config values; a CDN migration otherwise breaks deploys with no obvious connection to the change.
- **`secrets` is unavailable in a step-level `if:`** — using it there makes GitHub reject the entire workflow file, presenting as a run with zero jobs, no logs, and the file path shown where the workflow name should be. Guard inside the script instead (`env:` may reference secrets). Detector: `grep -nE '^\s*if:.*secrets\.' .github/workflows/*.yml`.

Full case study: knowledgeBase `patterns/release-publish-verification.md`.

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

### Static copy collision on re-deploy

When deploying via `cp -r .next/static .next/standalone/.next/` on the VM, the copy **fails with a "same file" error** if a symlink already exists at `.next/standalone/.next/static` from a previous deploy. Remove the target first:

```bash
ssh "$VM" "rm -rf $VM_DIR/.next/standalone/.next/static && cp -r $VM_DIR/.next/static $VM_DIR/.next/standalone/.next/"
```

A symlink at the copy destination (from an earlier postbuild or hand-placed) causes `cp -r` to write into the symlink's target directory, not replace it — or fail outright. `rm -rf` before the copy is idempotent: it harmlessly no-ops if nothing is there.

Source: finance-tracker `dfb291b` (2026-06-26).

## GitHub Pages Static Export (No-Server Alternative)

For apps that don't require SSR, auth, or server-side API routes, `output: 'export'` produces a static site that can be hosted on GitHub Pages for free — no VM, no PM2, no Apache config needed.

```ts
const nextConfig: NextConfig = {
  basePath: "/repo-name",   // must match GitHub Pages subpath
  output: "export",
  images: { unoptimized: true },  // required — no Image Optimization API
};
```

**CRITICAL: GitHub Pages requires a PUBLIC repo on free GitHub plan.** Making a repo private immediately breaks GitHub Pages — the site goes 404. If a site must be private (e.g., it embeds the production domain or sensitive content), host on VM Apache with `Alias /path /var/www/dir` instead. Source: netflix-social-platform (2026-07-01) went private for panel prep → GitHub Pages broke → switched to Apache Alias at `/var/www/games-social`.

**When to use GitHub Pages over VM PM2:**
- Pure demo/portfolio/static-content apps with a PUBLIC repo
- No server-side API routes, database, or OAuth
- No need for Apache ProxyPass config
- App is public (no auth gate needed) AND repo can stay public

**When to stay on VM PM2:**
- Needs dynamic API routes, SQLite, or server-side rendering
- Needs Google OAuth or any server-side auth
- Needs a Docker bridge or external service integration
- Needs Discord notifications, webhooks, or cron jobs

**Deploy pattern (GitHub Actions):** Push a workflow that runs `next build` and uploads the `out/` artifact to gh-pages. Requires `contents: write` permission on the Actions token — if the repo lacks it, use the manual pattern below.

**Deploy pattern (manual gh-pages branch, no Actions):** `next build` with `output: 'export'` **wipes `out/` entirely at the start of every build**, deleting any `.git` you initialized there. Never `git init` inside `out/` expecting it to survive the next build. Instead use a temp dir outside the project:
```bash
npm run build
rm -rf /tmp/deploy-staging && cp -r out /tmp/deploy-staging
cd /tmp/deploy-staging && touch .nojekyll
git init -q && git checkout -q -b gh-pages && git add -A
git commit -q -m "Deploy $(date -u +%FT%TZ)"
git push -f <repo-url> HEAD:gh-pages
```
Source: netflix-social-platform deploy.sh (commit 62e4dd4, 2026-06-30 — learned after the initial attempt had its `out/.git` wiped by `next build`).

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

## Apache Lowercase Rule Breaks Vite SPA Asset Hashes

The production VM's Apache vhost has a global rule that 301-redirects any URL with uppercase letters to its lowercase form (`RewriteMap lc int:tolower` / `RewriteRule ^(.*)$ ${lc:$1} [R=301,L]`). Vite builds emit mixed-case content hashes (e.g., `index-BqcsSXEO.js`); every JS/CSS asset 301s to a lowercase 404, so the page HTML returns 200 but the app never boots. Next.js `/_next/static/` hashes happen to be lowercase, so Next.js apps deployed on the same server are unaffected — only new Vite-based SPAs hit this.

**Symptom:** New SPA "doesn't load / loads forever" after deploy. Page HTML returns 200 but every JS/CSS asset 301s → 404.

**Fix:** Add an exemption for the new app's subpath before the lowercase rule in the Apache vhost:
```apache
RewriteCond %{REQUEST_URI} !^/my-spa-path
```

**Cloudflare cache gotcha:** The 301 response is cached at the CDN edge (~4h, `max-age=14400`). The CDN API token lacks Cache-Purge scope, so after adding the exemption you must either wait ~4h or force a new asset hash by triggering a rebuild with a minor change. Diagnosed 2026-06-23.

## .env Protection During rsync Deploys

When using `rsync --delete` to deploy, **always `--exclude '.env'`**. The `--delete` flag removes server-side files not in the source, which will overwrite the production `.env` (with its production-specific values like database ports, API endpoints) with local dev config.

```bash
# GOOD: Exclude .env from rsync
rsync -az --delete --exclude '.env' --exclude 'node_modules' ./dist/ "$DEPLOY_TARGET"

# BAD: rsync --delete with no .env exclusion
rsync -az --delete ./dist/ "$DEPLOY_TARGET"
```

**Post-deploy .env integrity check:** After rsync, verify critical env vars on the server still have production values. A silent overwrite causes hard-to-diagnose failures (e.g., wrong database port, wrong API base URL) that look like application bugs.

**Also exclude SQLite WAL files.** Apps using `better-sqlite3` or any SQLite WAL-mode database write live WAL/SHM files alongside the database file. `rsync --delete` will wipe these mid-transaction if they're not excluded:

```bash
rsync -az --delete \
  --exclude '.env' \
  --exclude '*.db' \
  --exclude '*.db-wal' \
  --exclude '*.db-shm' \
  --exclude 'node_modules' \
  .next/ "$DEPLOY_TARGET/.next/"
```

**Why:** A deploy that rsync'd without WAL exclusions wiped the live WAL file mid-write, corrupting the database state and requiring a restart to recover. Database files and WAL/SHM sidecars must always be excluded from rsync --delete deploys.

**Why this matters:** A real deploy overwrote a production database port with a local dev port, causing all connections to fail silently. The root cause was `rsync --delete` without `--exclude .env`.

## Pre-Deploy Backup + Automatic Rollback for rsync Deploys

For artifact-only (non-git) deployments using rsync, take a server-side backup of the current build before deploying and roll back automatically if the health check fails.

```bash
# 1. Backup current build on the VM before rsync
ssh "$VM" "cp -r .next .next-backup && cp server.js server.js.bak"

# 2. rsync new build (with WAL + .env exclusions)
rsync -az --delete --exclude '.env' --exclude '*.db' --exclude '*.db-wal' --exclude '*.db-shm' \
  .next/ "$VM_PATH/.next/"
scp .next/standalone/server.js "$VM:$VM_PATH/server.js"

# 3. Restart and health check
ssh "$VM" "pm2 restart $APP && sleep 4 && curl -sf http://localhost:$PORT/api/health"

# 4. On failure, rollback and exit 1
if [ $? -ne 0 ]; then
  ssh "$VM" "mv .next-backup .next && mv server.js.bak server.js && pm2 restart $APP"
  exit 1
fi
```

**When to use:** Any Next.js standalone app deployed via rsync to a non-git VM directory (the "flat-layout" pattern where PM2 runs `node ./server.js` from the app root, not from `.next/standalone/`). Apps deployed via `git pull + npm run build` on the VM use git as the rollback mechanism instead.

**Flat-layout note:** When PM2 is configured to run `node ./server.js` from the project root (not `.next/standalone/server.js`), deploying only `.next/` leaves a stale root `server.js`. Always `scp .next/standalone/server.js` back to the root as a separate step.

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

**WSL-to-VM artifact-only deploy sequence (stop → rsync → patch → symlink → start):**

For apps where the VM dir is artifact-only (no git repo), use this sequence to avoid file conflicts, appDir mismatch, and start.sh guard failures:

1. Build locally: `npm run build`
2. Stop PM2 BEFORE copying: `ssh $VM "pm2 stop <app>"` — avoids file-in-use conflicts during rsync
3. Rsync standalone and static dirs:
   ```bash
   rsync -az .next/standalone/ "$VM:$REMOTE_DIR/.next/standalone/"
   rsync -az .next/static/ "$VM:$REMOTE_DIR/.next/static/"
   ```
4. Patch `appDir` in `required-server-files.json` to the production path (both root-level copy and the copy inside `.next/standalone/`). Failure causes Next.js to detect a build-dir mismatch and trigger an unwanted on-VM rebuild at next start.
5. Create a `node_modules` symlink to satisfy `start.sh`'s npm-install guard:
   ```bash
   ssh $VM "ln -sfn $REMOTE_DIR/.next/standalone/node_modules $REMOTE_DIR/node_modules"
   ```
   Without this, `start.sh` finds no `node_modules/` at `$REMOTE_DIR/` and attempts `npm install` — which fails (no `package-lock.json` in an artifact-only dir). The symlink points to the already-bundled modules inside `.next/standalone/`.
6. Start with `pm2 start` (NOT `pm2 restart`): after `pm2 stop`, the process is in `stopped` state; `pm2 restart` on a stopped process may not bring it online.

Source: travel-assistant standalone deploy script (commit 1122624, 2026-06-27).

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

## Next.js Flat Layout — Employ Deploy Model Exception

Most VM-hosted Next.js apps use the standard **nested standalone layout**: PM2 runs `node .next/standalone/server.js` from inside `.next/standalone/` (or equivalent `start.sh`).

**Employ uses a flat layout:** PM2 runs `node server.js` from the app root. `server.js` and `start.sh` live at the root alongside `.next/`. The repo's deploy script copies standalone artifacts flat to the app root rather than into a `standalone/` subdir.

**Staging-to-prod promotion gotcha:** When the `/staging` skill promotes employ to production, the rsync must include root-level `server.js` and `start.sh` in addition to `.next/`. Promoting only `.next/` leaves stale root files, causing PM2 to run outdated code silently. Source: employ `claude-skills` staging updates (commits `1a20372`, `a2d5c7c`, 2026-06-28).

**Staging port assignments — do not reuse ports already bound by running services:**

| App | Staging Port | Conflict to avoid |
|-----|-------------|-------------------|
| shopper | 3090 | — |
| foodie | 3094 | — |
| travel | 3116 | 3112 is browser-logs |
| employ | 3116 | 3112 is browser-logs |

Before assigning a new staging port, check existing PM2 processes and `~/repos/scripts/` for bound ports.

## Next.js Behind Reverse Proxy: Use `AUTH_URL` for Generated URLs, Not `req.nextUrl.origin`

In Next.js apps served behind Apache `ProxyPass` (shopper, foodie, travel-assistant), `req.nextUrl.origin` resolves to the **internal server address** (e.g., `http://127.0.0.1:3009`), not the public domain. Any URL built from `req.nextUrl.origin` — share links, email links, webhook callbacks — will be broken for the end user.

**Fix:** Use `process.env.AUTH_URL` as the base for all generated URLs. `AUTH_URL` is already set to the correct public base URL in each app's `.env`.

```ts
// WRONG — returns internal address behind proxy
const shareUrl = `${req.nextUrl.origin}/app/share/${token}`;

// CORRECT — uses the public base from env
const baseUrl = process.env.AUTH_URL || "https://your-domain.com";
const shareUrl = `${baseUrl}/app/share/${token}`;
```

**Why:** The same class of bug hit three Next.js apps simultaneously (2026-07-02). `req.nextUrl.origin` was used after a prior refactor that stopped using `AUTH_URL` as the base. `req.url` and `headers.get('host')` have the same problem behind a non-HTTPS proxy.

**Self-review trigger:** Any route handler that builds a URL for external consumption (share link, redirect, email, webhook) must use an env-configured base URL, not anything derived from the request object.

## VM SSH — Rapid Bursts Trip fail2ban (Port 22 Banned ~10 min)

**Never fire a burst of short SSH connections to the GCP VM, and never kill a deploy SSH session mid-run then immediately retry.** The VM runs fail2ban on port 22; roughly 5 rapid or aborted connections from the same source IP trigger a ~10 minute DROP ban.

**Symptom:** SSH connect TIMES OUT (not "connection refused"). ICMP is also blocked. The production web tier still returns HTTP 200 through Cloudflare (CDN serves cached responses), so the site looks healthy — the only new signal is port 22 timing out. Direct-to-origin ports 80/443 are always firewalled to Cloudflare-only.

**Recovery:** Stop all SSH attempts immediately — each retry re-extends the ban. Wait 10-12 minutes, then make ONE clean connection.

**Prevention:**
- Run all deploy steps inside a **single SSH invocation** with a generous timeout (180s+), not a sequence of short separate connections.
- Avoid a trailing `pm2 jlist | python ...` parse that can hang the session near the timeout boundary and tempt a kill-and-retry loop. If you need status, give the whole command room (timeout 180s) or split status into a later, separate single connection.
- If a deploy SSH session hangs, wait for the natural timeout rather than killing and retrying immediately.

### rsync --chmod=D755,F644 for web-root deploys (mktemp staging perms trap) (2026-07-17)
See memory infra_rsync_mktemp_perms: rsync -a from a mktemp -d staging dir propagates mode 700 onto the destination dir; Apache 403s everything beneath. Always rsync -a --chmod=D755,F644 when deploying to a web root.

### Pin Prisma binaryTargets to the deploy runtime's OpenSSL; never ship a build from a different-OpenSSL host to the VM (2026-07-19)
A Next.js standalone + Prisma app on the production VM (Node links OpenSSL 1.1.1w = debian-openssl-1.1.x) went totally DB-dark on 2026-07-18/19: every DB route/cron returned HTTP 500 with an EMPTY body, homepage still 200'd (static shell) so uptime checks missed it. Cause: prisma/schema.prisma had no binaryTargets, so prisma generate emitted only the build host's engine. A build produced on the WSL dev clone (OpenSSL 3.0.13 = debian-openssl-3.0.x) was shipped out-of-band to the VM, bundling only libquery_engine-debian-openssl-3.0.x into .next/standalone/node_modules/.prisma/client. VM runtime needs 1.1.x -> PrismaClientInitializationError: could not locate the Query Engine. Diagnosis tell-tales: the error's 'searched locations' list names the build-host dev path (/home/npezarro/repos/...); the live-dir reflog head is 'pull: Fast-forward' not deploy.sh's 'reset --hard origin/main' (out-of-band build, same delivery anti-pattern as the static-asset 'styling broke' outage but it breaks the DB layer instead of CSS). Fix (both): (1) pin binaryTargets = [native, debian-openssl-1.1.x, debian-openssl-3.0.x] in schema.prisma so any build host bundles the VM's engine; (2) redeploy via the app's ./deploy.sh, which runs prisma generate ON the VM (native = 1.1.x) and rebuilds standalone with both engines. Verify: a DB-touching endpoint returns 200 and ls .next/standalone/node_modules/.prisma/client shows the 1.1.x engine.

### Verify the shipped standalone bundle after an rsync-promote, not just health 200 (2026-07-24)
During the travel-assistant deploy, the staging→prod promote `rsync -a --delete <stg>/.next/ <prod>/.next/` exited 0 and `/api/health` returned 200, but `.next/standalone/` was NOT updated: prod's `app/api/query/route.js` still referenced the OLD content-hashed chunks and none of the new code shipped. A plain `rsync -a` (size+mtime quick-check) silently under-transferred the standalone chunks; re-running with `--checksum` fixed it and the change's marker string appeared. Lesson for the staging skill Step 6 promote: after the artifact rsync, `grep -rl '<a-new-literal-or-symbol-from-the-change>' <prod>/.next/standalone/.next/server/` BEFORE restarting or declaring success. Health 200 and "rsync done" both lie here because the route module isn't executed until a real request renders it. Prefer `rsync -a --checksum --delete` for standalone `.next` promotes.

### Cloudflare cache rules are LAST-match-wins; MCP servers should use token auth not OAuth when headless consumers exist (2026-07-29)
Two corrections from the 2026-07-29 Cloudflare MCP session.

1. CACHE RULE ORDERING. Cloudflare cache rules are **last**-match-wins, not first. CF docs: 'When multiple rules specify the same setting, the last matching rule wins.' Verified on the production zone: an `/<app>/_next/` bypass at array index 2 overrides the broader `/<app>` caching rule at index 1 (asset serves cf-cache-status: DYNAMIC). To carve an exception out of a broad caching rule, place the exception AFTER it. When debugging 'my bypass is not working', look for a LATER rule re-enabling cache, not an earlier one.

   This claim was previously WRONG in two places: the cloudflare-site-setup skill and the 2026-06-02 migration closeout (which was the origin; it propagated into the skill). Both corrected. Lesson: one topic documented in two places is how a wrong claim survives.

2. MCP AUTH FOR HEADLESS ECOSYSTEMS. Vendors label OAuth 'recommended' for MCP servers, but OAuth-authenticated MCP servers are ABSENT from headless 'claude -p' runs (autonomousDev, learning-agent, VM #requests worker, Docker bridges). Prefer a Bearer API token when the server supports one, even when the setup docs only mention OAuth (check the server's README; the vendor setup page mentioned only OAuth while the server's own README documented a token path). Verify at CONNECT time via a raw JSON-RPC initialize, not at config-write time, and revert the config if it fails rather than leaving a permanently-401ing server in place.

3. SCOPE PROBING. When a vendor rejects a credential for scope, you usually cannot introspect it. Probe by calling endpoints and read RESULT CONTENTS, not the success flag: a zone-scoped Cloudflare token returns success:true with an EMPTY array from /accounts. Permissions are sectioned; adding more of the wrong section never helps (two Zone-scoped tokens failed identically before Account Settings:Read was added).

## Order Deploy Steps So Failures Abort Before the Service Is Torn Down

A deploy script that stops/deletes the running service *before* it does anything that can fail turns every such failure into an outage with no rollback — and, worse, a silent one when an auto-heal cron keeps retrying it.

**Observed (runeval, 2026-08-04, two months undetected):** `deploy.sh` deleted the PM2 process at step 4, then ran `prisma migrate deploy` at step 5 under `set -e`. A broken migration table made step 5 fail every time, so each deploy killed the app, died on the migration, and left a half-built `.next`. An asset-heal cron re-ran the same deterministically-broken deploy 10 minutes later, so the app kept reappearing and nobody noticed that **merged code had stopped reaching production entirely**. A feature merged to `main` and reported "done" was absent from the running build and its table absent from the DB.

Rules:
- **Put every check that can fail before the teardown.** A read-only pre-flight that aborts with the old version still serving beats a teardown that aborts halfway. Cheap checks (DB reachable, migrations parseable, disk free, required env present) cost seconds.
- **"Merged" is not "deployed."** When a feature is reported complete, verify the *running* artifact: the route exists in the built output, the table exists in the DB, and the endpoint answers. A commit on `main` proves none of that.
- **An auto-heal cron that retries a deterministically failing deploy converts a loud failure into a silent one.** Healing loops need a consecutive-failure counter that escalates instead of retrying forever.
- **A deploy script must not dirty its own tree.** The same script's `npm install` rewrote `package-lock.json`, so its own step-1 dirty-tree check aborted the *next* run — it blocked itself after one success. If a build step mutates a tracked file, discard exactly that file before the check, and keep the check narrow so real uncommitted work still aborts loudly.

### Never hand-write migration-bookkeeping rows

Inserting rows into `_prisma_migrations` (or any migration ledger) by hand to "mark a migration as applied" produces rows the tool cannot parse, and the damage surfaces far from the cause. Prisma requires the `checksum` to be the 64-char lowercase hex SHA-256 of that migration's `migration.sql`, and `started_at`/`finished_at` to be **integer epoch-millis**; placeholders (`'manual'`, `'skip'`) and TEXT datetimes both break it.

Use the supported command, which computes the right values: `npx prisma migrate resolve --applied <migration_name>`.

**Diagnosing it:** the failure is `Error in Schema engine ... ConversionError("input contains invalid characters")` — that string is **chrono's date-parse error**, not a corrupt database. It reproduces against *any existing* DB file (including a copy in `/tmp`) and disappears against a fresh one, which sends you hunting a corrupt DB or a bad engine binary. Bisect by creating an empty SQLite file and running the same command against it; if that works, the problem is data in the ledger, not the engine.

## Monitor Freshness Separately From Liveness

The reason the outage above lasted two months is not that the deploy broke. It is that **nothing was watching the axis it broke on.** A half-failed deploy leaves the app *up on old code*, and every liveness monitor is then honestly green:

| monitor | what it asked | answer on a stale build |
| --- | --- | --- |
| uptime / HTTP check | does it return 200? | yes — the old build serves fine |
| process watchdog | is the process online? | yes |
| static-asset drift | does the in-memory build match disk? | yes — both stale, and consistent |
| error aggregator | is it throwing? | no — old code that used to work still works |

"Up" and "current" are independent properties, and **liveness monitoring cannot detect a freshness failure by construction.** Adding more uptime checks would never have caught this; the missing check asks a different question: *is the deployed commit the one on the release branch?*

When this check was finally written and run across the fleet, runeval was not the only victim — one online app was **6 commits / 46 days** behind (including two merged bug fixes), another 3 commits / 22 days, and one was serving an autonomous bot's feature branch. None had ever alerted. Assume this class of drift is present and unmeasured until something measures it.

Rules:
- **Compare each running app's `HEAD` to its upstream branch on a schedule.** Cheap, and it is the only signal that distinguishes "deployed" from "merged".
- **Age the drift by the OLDEST unshipped commit, not the newest.** A steady stream of merges keeps resetting a newest-commit clock, so a deploy broken for weeks looks perpetually "just merged". The alertable question is "code merged N days ago is still not running".
- **Only alert for apps that are actually serving.** A stopped app on old code is dormant, not an outage; alerting on it trains people to ignore the channel.
- **Also flag non-canonical branches and missing upstreams.** An app deployed off a bot's feature branch can be arbitrarily far from the release branch while the commit-count `behind` reads 0 — that drift is invisible to a count alone.
- **Detect, do not auto-heal.** A cron that redeploys on drift is how the original loud failure became a silent one. Escalate to a human or agent and let them run the app's own deploy script.
- **Give it a grace window** (~12h) so the normal gap between merge and the next deploy is not noise.
- **Make the monitor fail closed.** The first version of this check resolved `pm2` from an inherited `PATH`. Under a reduced environment `pm2` was not found, every app fell through to "not serving", and the script exited **0 having checked nothing** — a monitor that reads green while covering zero apps, which is the exact failure class it was built to catch. Set `PATH` explicitly, verify each required binary up front, and treat "cannot enumerate targets" as a loud alert and a non-zero exit, never as an empty result set. Test this by running the monitor under `env -i`: if it exits 0 and reports nothing wrong, it is lying.

**Generalize past deploys:** any failure that leaves a system serving *stale but valid* output is invisible to health checks — stale caches, a paused replica, a cron that stopped writing, an expired feed still serving its last good payload. Wherever correctness depends on data being *recent*, monitor recency explicitly; "it responded" is not evidence that it responded with *current* data.

### Next.js standalone builds break inside a nested git worktree -- build deploy artifacts from the canonical checkout (2026-08-04)
Observed 2026-08-04 in shopper. Working in a git worktree at .claude/worktrees/<name> (inside the repo, per the agent.md multi-edit rule), 'npm run build' compiled cleanly but its post-build step failed:

  cp: cannot create directory '.next/standalone/.next/static': No such file or directory

Cause: Next.js resolves its file-tracing root to the directory that owns node_modules -- the main repo checkout, not the worktree. So the standalone output is emitted at .next/standalone/.claude/worktrees/<name>/server.js instead of .next/standalone/server.js, and the build script's 'cp -r .next/static .next/standalone/.next/static' has no target directory.

This is a layout artifact, not a code defect: the compile, typecheck and lint all pass, and the same commit builds cleanly (exit 0, static copy included) from the canonical checkout.

Rules:
- Use the worktree to EDIT and to run unit tests; do the deploy build from the canonical checkout after merging.
- Do not read the cp failure as a broken build and start debugging next.config.ts. Check where server.js actually landed first: find .next/standalone -maxdepth 6 -name server.js
- The /staging skill is unaffected because it clones fresh into /var/www/staging-<app> on the VM, which is a normal checkout.
- rm -rf the worktree's .next when done, so a half-built tree is not mistaken for a deployable artifact.
