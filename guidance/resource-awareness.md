<!-- Load when: server resource checks -->
# Resource Awareness

Shared infrastructure has limits. Discover them before you hit them — don't memorize numbers that change.

## Principle: Discover, Don't Memorize

Server specs change (VMs get resized, processes get added, disk fills up). Never hardcode thresholds in your mental model. Instead, **check before every heavy operation**.

## Before Heavy Work

Run these checks before starting builds, installs, large file operations, or anything CPU/memory-intensive:

```bash
# Memory — is there enough for a build?
free -m

# Disk — is there room for node_modules, build output, logs?
df -h

# What's already running? How many processes, how much memory?
pm2 jlist 2>/dev/null | python3 -c "
import sys, json
procs = json.load(sys.stdin)
for p in procs:
    print(f\"{p['name']:20s} {p['pm2_env']['status']:8s} {p['monit']['memory']//1024//1024}MB\")
" 2>/dev/null || pm2 list

# CPU load
uptime
```

If memory is tight (< 500MB free) or disk is low (< 1GB), flag it before proceeding. Don't silently start a build that will OOM-kill something else.

## Output Size Awareness

Large responses create problems downstream:
- Discord embeds truncate at ~3,900 characters — anything beyond is lost
- WordPress posts become walls of text that nobody reads
- Terminal output floods the user's scrollback

**Keep responses focused.** If you need to output large content (full file listings, extensive logs, audit results), write it to a file and reference the path. Don't dump it into your response.

## Concurrent Job Awareness

On shared infrastructure, you're probably not the only process running:
- **Check before starting resource-intensive work.** `pm2 list` shows what else is running. If three other agent sessions are active, a `npm install` might push the server over.
- **Check `#running-job-logs`** (if Discord is available) to see if other Claude sessions are active on the same server.
- **Don't spawn parallel builds** on a constrained VM. Sequential is slower but won't OOM.

## Environment Variable Awareness

Before starting work on any deployed project:
- **Check if env vars are loaded:** `echo $NODE_ENV`, check `.env` exists
- **Understand the build/restart distinction:** Static site generators (Next.js, Vite) bake env vars at build time. Changing `.env` requires a full rebuild, not just a PM2 restart

## Pin pnpm to 10.x on shared infrastructure — 11.x silently drops native builds (2026-08-04)

Migrating an app's `node_modules` to pnpm is a legitimate disk-saving move on infrastructure hosting many Node apps (pnpm hardlinks every package from one content-addressed store, so each additional app costs only its unique packages, not a full private tree). But the fix is version-sensitive:

- pnpm 10+ blocks dependency build scripts by default; native modules (e.g. `better-sqlite3`) need an explicit allowlist via `pnpm.onlyBuiltDependencies` in `package.json`. In pnpm 10.x this works.
- **In pnpm 11.20.0 it silently does not.** The `package.json` field is ignored outright (pnpm warns "the pnpm field in package.json is no longer read"), and moving the same allowlist into `pnpm-workspace.yaml` still leaves the native module with no compiled `build/Release/*.node` binding. **The install still exits 0** — the failure only surfaces later, the first time the module is `require()`'d at runtime.
- **Rule: keep pnpm pinned to 10.x** on any shared host. Do not run `npm i -g pnpm@latest` there. After any pnpm version change, verify a native module actually *loads*, not just that install exited 0: `node -e "require('better-sqlite3'); console.log('ok')"`.

Other traps from the same migration, worth checking before assuming a pnpm move is complete:
- Use `node-linker=hoisted` in `.npmrc` (committed) — a flat, npm-compatible layout avoids Next.js standalone file-tracing's known edge cases with symlinked deps, and still hardlinks from the store so the disk saving is unaffected.
- Convert lockfiles with `pnpm import` (`package-lock.json` → `pnpm-lock.yaml`, identical resolved versions). Never migrate an app with no existing lockfile — a fresh resolve drifts versions and confounds any breakage that follows.
- Prisma needs an explicit `pnpm exec prisma generate` in the deploy script; the build-script allowlist alone does not generate the client. Prisma 7 emits TypeScript to a custom output path, so `require('@prisma/client')` is the wrong liveness check for those apps.
- Put any `node_modules` rollback backup **outside** the project directory — left inside, build/validate scripts walk it and fail on it.
- A deploy script that still runs plain `npm install` silently reverts the migration on its next run; migrate the deploy script in the same commit as the lockfile swap.
- Next.js standalone apps don't read the top-level `node_modules` at runtime (a correctly-migrated app can ship a 0MB top-level tree), so migrating it cannot break a currently-running app — the risk is entirely deferred to the *next* build.
- **Check `MAX_CONCURRENT_JOBS`** or equivalent throttle settings in the environment before spawning background processes
