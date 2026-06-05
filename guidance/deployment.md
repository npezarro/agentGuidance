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

## Stop PM2 Before Next.js Standalone Builds

`next build` deletes `.next/standalone/server.js` before recreating it. If PM2 is running and the process restarts (for any reason) during this window, PM2 crash-loops on `MODULE_NOT_FOUND` until the build finishes. With `max_restarts: 10` or higher, this can burn through all restart attempts before the build completes, leaving the process errored.

**Fix:** Always stop PM2 before building a standalone Next.js app:
```bash
pm2 stop <process>; npm run build && pm2 restart <process> --update-env
```

Use `;` (not `&&`) after `pm2 stop` so the build proceeds even if the process was already stopped or doesn't exist yet (first deploy).

**Why:** runeval observed 27+ PM2 restart attempts during a single build window (2026-06-03). The build completed successfully but PM2 had already entered "errored" state.

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
