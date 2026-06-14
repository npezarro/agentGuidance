# Process Hygiene

Track what you start. Clean up what you leave behind.

## Track What You Start

If you spawn a long-running process — `npm run dev`, a background build, a watch command, a test runner in watch mode — you own it for the duration of your session.

- **Record the PID or process name** when you start something. You'll need it to stop it later.
- **Stop it before session end** or document it in `context.md` so the next session knows it's running.
- **Don't assume PM2 will manage it.** Only processes in `ecosystem.config.cjs` (or equivalent) are managed. Anything you start with `node`, `npm run dev`, or `&` is orphaned when your session ends.

```bash
# Start a dev server — note the PID
npm run dev &
DEV_PID=$!
echo "Dev server running on PID $DEV_PID"

# Later, clean up
kill $DEV_PID
```

## Atomic State Writes

When updating `context.md` or `progress.md`, treat the update as its own operation — don't leave it as the last step in a chain that might not complete.

- **Update context files early and often**, not just at session end
- **Commit the context update with the work it describes**, in the same commit
- If you're about to do something risky (a build, a deploy, a large refactor), update `context.md` *before* the risky step so that if it crashes, the state is captured

## Temp File Cleanup

- Don't leave temp files in `/tmp`, project directories, or anywhere else
- If you create scratch files during debugging (`test.js`, `debug.log`, `temp.json`), delete them before committing
- If a process creates temp files (detached job output, build artifacts), clean them up or document their location

## Port and Process Conflicts

Before starting any server or service:

```bash
# Is the port already in use?
ss -tlnp | grep <port>

# Is a previous instance still running?
ps aux | grep <process-name>
pm2 list
```

Don't blindly start a service on a port that's occupied. Either stop the existing process (if it's yours) or use a different port. If the existing process belongs to another session, coordinate — don't kill it.

### PM2 Restart EADDRINUSE Crash Loop

When PM2 restarts a process, the old Node instance may not release its port before the new one starts, causing `EADDRINUSE` → crash → PM2 restart → repeat.

**Three-layer fix:**

1. **`kill_timeout` and `listen_timeout` in ecosystem.config:**
   ```js
   { kill_timeout: 3000, listen_timeout: 3000 }
   ```
2. **Graceful shutdown handler in server code** — handle both SIGINT and SIGTERM, add a force-exit fallback, and register global error handlers:
   ```js
   function gracefulShutdown(signal) {
     server.close(() => process.exit(0));
     // Force exit if connections don't drain within 10 seconds
     setTimeout(() => process.exit(1), 10000);
   }
   process.on('SIGINT', () => gracefulShutdown('SIGINT'));
   process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
   process.on('unhandledRejection', (reason) => console.error('Unhandled Rejection:', reason));
   process.on('uncaughtException', (err) => { console.error('Uncaught Exception:', err); setTimeout(() => process.exit(1), 100); });
   ```
   - SIGINT handles Ctrl-C in dev, SIGTERM handles PM2 restart. Both are needed.
   - The 10-second force-exit prevents PM2 from hanging on keep-alive connections that never drain.
   - `unhandledRejection`/`uncaughtException` log before exiting; without these, PM2 sees a silent crash with no diagnostic output.
   - Source: pezantTools server.js (2026-05-28).
3. **Use a `start.sh` wrapper for Next.js standalone** — `next start` as the PM2 script loses process tracking. A wrapper lets PM2 signal the actual node process:
   ```bash
   #!/bin/bash
   set -e
   set -a
   if [ -f "$(dirname "$0")/.env" ]; then source "$(dirname "$0")/.env"; fi
   set +a
   # Check for both server.js AND static assets — server.js can exist from a partial build
   if [ ! -f "$(dirname "$0")/.next/standalone/server.js" ] || [ ! -d "$(dirname "$0")/.next/standalone/.next/static" ]; then
     npm run build
   fi
   exec node "$(dirname "$0")/.next/standalone/server.js"
   ```
   - Build script must use `mkdir -p .next/standalone/.next` before `rm -rf .next/standalone/.next/static` — on a fresh clone the directory doesn't exist and `cp` will fail silently. Correct form: `next build && mkdir -p .next/standalone/.next && rm -rf .next/standalone/.next/static && cp -r .next/static .next/standalone/.next/static`

**Diagnosis:** `pm2 show <process>` with rapidly increasing restart count + `EADDRINUSE` in logs = this pattern. Source: shopper and pm-interview-practice (2026-05-15).

## Docker Bind Mount Refresh

**`docker compose restart` does NOT refresh bind mounts.** When a container is restarted with `docker compose restart`, the container process is restarted but the container itself is not recreated. Bind mount inodes remain stale, so any files updated on the host (e.g., credential files, OAuth tokens) are not visible inside the container until the container is recreated.

**Fix:** Use `docker compose down && docker compose up -d` instead of `docker compose restart` for any operation that requires the container to pick up updated host files:

```bash
# WRONG — container process restarts but bind mount stays stale
docker compose restart

# CORRECT — container is fully recreated, bind mounts are fresh
docker compose down && docker compose up -d
```

**When this matters most:**
- Auth refresh cron jobs that regenerate credential files on the host and expect the container to use them
- Any post-rotate token handoff from host to containerized service

**Diagnosis:** If a cron-based recovery script keeps looping (restarting the container repeatedly without recovering), but the credential file on the host is valid, this is the likely cause. The container is holding a stale mount.

**Source:** shopper auth refresh cron (commit b5c2338, 2026-05-24) — cron restart loop ran for days because `restart` never picked up refreshed credentials.

## Docker `exec` Always Needs `--user`

When running `docker exec` against a container that has a non-root application user (e.g. the bridge containers run the `node` user), **always pass `--user <username>`** on every exec call. Without it, `docker exec` runs as root — files written inside the container (credentials, config) land in `/root/` instead of `/home/<user>/`, and the application process (running as `node`) cannot read them.

```bash
# WRONG — exec runs as root, credentials written to /root/.claude/
docker exec "$CONTAINER" sh -c 'echo data > /home/node/.claude/credentials.json'

# CORRECT — exec runs as node, credentials land where the app reads them
docker exec --user node "$CONTAINER" sh -c 'echo data > /home/node/.claude/credentials.json'
```

**Why silent:** The exec command succeeds (exit 0), the file is written, but the bridge process reads a different path. Auth stays broken with no obvious error.

**When this applies:** Any `docker exec` that writes or reads user-owned files (credential rotation, config injection, Claude CLI auth refresh). The `CONTAINER_USER` env var pattern (default `"node"`) makes this portable across containers. Slim images often don't have `procps` — swap `pkill` for `ps | awk | kill`.

**Source:** `scripts/claude-auto-relogin-container.sh` bugfix (commit 3f211e9, 2026-05-28) — OAuth token rotation silently failed because exec ran as root.

## Long Text Transfer

Never give the user long commands, URLs, or multi-line text to copy-paste manually. Termius and other SSH clients mangle long pastes (newline parsing, line wrapping).

**Instead:**
- **Long commands (>~80 chars):** Write to a temp script file (e.g., `/tmp/run-me.sh`), then give a short `scp` + `bash` command
- **Long URLs:** Write to a file and `scp`, or use a short redirect
- **Multi-step commands:** Break into individual short lines, never chain with `&&` for paste
- **Short commands (<80 chars):** Direct paste is fine

**Why:** Repeated incidents of mangled pastes causing failed commands. The user works in Termius SSH client which breaks on multi-line and long-string paste. Writing to files and transferring is always reliable.

## SCP Over Reverse SSH Tunnels

`scp` hangs indefinitely when used over the reverse SSH tunnel (VM → localhost:2222 → WSL). The SSH command channel works fine, but the SCP data channel negotiation fails silently.

**Why:** Reverse tunnels forward the SSH control channel correctly, but SCP's separate data channel negotiation fails silently over loopback tunnels.

**Fix:** Use `ssh+cat` piping for file transfers over the reverse tunnel:
```bash
# Instead of: scp vm:remote/path local/path
ssh -p 2222 localhost 'cat /remote/path' > local/path

# Or push from VM to local:
cat local/path | ssh -p 2222 localhost 'cat > /remote/path'
```

**When this applies:** Any file transfer from the VM to local WSL workers via the reverse tunnel. Direct VM→WSL paths via the tunnel are fine for commands, only broken for file data.

**Source:** Discord bot media-transfer bug (2026-05-28) — Discord image attachments silently never arrived at local workers because `scp` hung indefinitely over the tunnel.

## Cron Cooldown Guard

When a PM2-managed job runs on a schedule (cron trigger), external systems (fix-checker, manual restart, deploy scripts) can cause it to run outside its intended window. Add a **cooldown guard** to prevent duplicate runs:

- Check a timestamp file (e.g., `data/<name>-last-run.txt`) at startup. If the last run was within the cooldown window, exit early.
- Always support a `--force` flag to override the guard for manual runs.
- Write the current timestamp to the file after a successful run, not before.

**Why:** deal-scout's housing-scout ran ~24 times/day instead of once because fix-checker (10-min scan interval) retriggered it via the shared ecosystem config. Adding a 20-hour cooldown guard fixed this. Any scheduled job that runs via PM2 cron or `pm2 restart` is vulnerable to the same pattern.

## Node.js Concurrent-Run Lock File

For jobs where overlapping runs are the problem (two cron triggers 5 minutes apart, second fires before first finishes), use a **PID-based O_EXCL lock file** instead of a cooldown guard:

```javascript
const LOCK_FILE = path.join(__dirname, '..', 'backups', '.job.lock');

function acquireLock() {
  try {
    // O_EXCL: atomic create-or-fail — no race condition
    const fd = fs.openSync(LOCK_FILE, fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_WRONLY);
    fs.writeSync(fd, String(process.pid));
    fs.closeSync(fd);
    return true;
  } catch {
    // Lock exists — check if holder is still alive
    try {
      const pid = parseInt(fs.readFileSync(LOCK_FILE, 'utf8').trim());
      process.kill(pid, 0); // throws ESRCH if process doesn't exist
      return false; // lock holder still running
    } catch {
      // Stale lock — remove and retry once
      try { fs.unlinkSync(LOCK_FILE); } catch {}
      try {
        const fd = fs.openSync(LOCK_FILE, fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_WRONLY);
        fs.writeSync(fd, String(process.pid));
        fs.closeSync(fd);
        return true;
      } catch { return false; }
    }
  }
}

function releaseLock() {
  try { fs.unlinkSync(LOCK_FILE); } catch {}
}

if (!acquireLock()) {
  console.log('[job] Another instance already running, skipping.');
  process.exit(0);
}
process.on('exit', releaseLock);
process.on('SIGTERM', () => { releaseLock(); process.exit(0); });
process.on('SIGINT', () => { releaseLock(); process.exit(0); });
```

**Key differences from cooldown guard:**
- **Cooldown guard**: prevents re-runs within a time window (deal-scout, once per 20h)
- **Lock file**: prevents concurrent overlap (shopper recovery, prevents duplicate bridge slots being consumed)

**Why:** A 06:15 cron fire can overlap with a 06:10 run still processing through a slow bridge call (10-20 min). Lock file catches this; cooldown guard doesn't (it's based on when the job *started*, not whether it's still running). Source: shopper commit ba47e21.

## Stale Git Lock Files

When automated processes (hooks, cron jobs, PM2 services) get killed mid-git-operation (by hook timeout, OOM, SIGTERM), they leave `.git/index.lock` files that silently block all subsequent git operations in that repo. No error is surfaced to the caller; git commands simply fail.

**Real-world impact:** A hook timeout in claude-token-tracker left a lock file that blocked usage sync for an entire month. The `!usage` command showed "No sessions recorded" with no indication that a stale lock was the cause.

**Prevention:** Any automated script that runs git commands should check for and remove stale lock files before operating:

```bash
# Remove lock files older than 60 seconds (safe threshold)
LOCK_FILE="$REPO_PATH/.git/index.lock"
if [ -f "$LOCK_FILE" ]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE") ))
  if [ "$LOCK_AGE" -gt 60 ]; then
    rm -f "$LOCK_FILE"
    echo "Removed stale git lock (age: ${LOCK_AGE}s)"
  fi
fi
```

**Why 60 seconds?** Normal git operations complete in under a second. A lock older than 60 seconds is almost certainly stale. Don't remove younger locks, as they may belong to an active operation.

**Where this applies:** Any cron-triggered or PM2-managed process that does `git add`, `git commit`, or `git push` (trading-agent, learning-agent, fix-checker, token-tracker hooks, session-log sync).

## Bash `set -u` with Optional Parameters

When scripts use `set -u` (nounset), referencing an unset positional parameter like `$2` causes an immediate exit. This breaks scripts where positional args are optional.

**Fix:** Use `${N:-}` (empty default) or `${N:-default}` for any positional parameter that may not be passed:

```bash
# WRONG — exits if $2 is not provided under set -u
if [[ "$2" == "--bg" ]]; then

# RIGHT — defaults to empty string
if [[ "${2:-}" == "--bg" ]]; then
```

**Why:** browser-agent's CLI hit this (2cd17b7, 2026-05-15). The `open` command's `$2` was conditionally checked for `--bg` but failed when omitted. Applies to any script using `set -euo pipefail` with optional args.

## Bash `${VAR:-default}` vs `${VAR-default}`: Empty Counts as Unset

`${VAR:-default}` substitutes the default if `VAR` is **unset OR empty**. `${VAR-default}` substitutes only if `VAR` is **unset**. When a script intentionally sets a var to empty string to disable optional behavior, using `:-` silently ignores that intent.

```bash
export BRIDGES=""         # caller wants to skip the restart step

# WRONG — empty string treated as unset, defaults to "foodie shopper travel"
BRIDGES="${BRIDGES:-foodie shopper travel}"

# CORRECT — only substitutes when BRIDGES is genuinely unset
BRIDGES="${BRIDGES-foodie shopper travel}"
```

**When this matters:** Any script with optional feature flags passed as environment variables. If `FOO=""` should mean "disabled", use `${FOO-default}`. If `FOO=""` should mean "use default", use `${FOO:-default}`.

**Source:** `scripts/claude-auto-relogin.sh` bugfix (commit 3f211e9, 2026-05-28) — setting `BRIDGES=""` to refresh only the host account still restarted all bridges because `:-` treated the empty string as unset.

## Bash `set -e` Kills Error Handlers Before They Fire

When using `set -e` (errexit), a failing command causes the script to exit **immediately** before the next line executes. This makes bare `$?` capture after a command dead code — the error handler that reads `$?` never runs.

```bash
# WRONG — set -e exits after 'some_command' fails; EXIT_CODE=$? never executes
set -e
some_command
EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  notify_discord "Failed: $EXIT_CODE"   # unreachable
fi

# RIGHT — || captures exit code inline without triggering set -e
EXIT_CODE=0
some_command || EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  notify_discord "Failed: $EXIT_CODE"   # now reachable
fi
```

**Why:** autonomousDev-private's three runners + verify.sh had this bug: timeout logs, Discord alerts, and state-file writes were all dead code because `set -e` aborted before the inline `EXIT_CODE=$?` capture. All failure notifications silently never fired for months (f6e304e, 2026-06-09).

**How to apply:** In any `set -e` or `set -euo pipefail` script, capture exit codes inline with `cmd || VAR=$?`. Never write `cmd; VAR=$?` — the semicolon is still `set -e`-transparent and exits on failure.

## Bash `git stash pop` Must Be Guarded

Never call `git stash pop` unconditionally in a script. If the script stashed nothing (because the working tree was clean), an unconditional pop will dump a **pre-existing user stash** onto whatever branch is checked out, potentially overwriting unrelated in-progress work.

```bash
# WRONG — pops whatever is on the stash stack, even if this script didn't push it
git stash
# ... do work ...
git stash pop   # might dump user's saved state onto wrong branch

# RIGHT — track whether THIS script stashed, only pop what we pushed
STASHED=false
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  git stash --quiet && STASHED=true
fi
trap '[ "$STASHED" = true ] && git stash pop --quiet 2>/dev/null || true' EXIT
```

**Why:** autonomousDev-private's `verify.sh` had an unconditional `git stash pop` in its `trap cleanup EXIT`. Any user with staged work could have it silently overwritten when the verify script ran. Fixed in f6e304e (2026-06-09) by adding the `STASHED=false` guard flag.

## PM2 wait_ready Anti-Pattern

Do **not** set `wait_ready: true` in PM2 ecosystem configs unless the app explicitly calls `process.send('ready')` after initialization.

Without that signal, PM2 treats every startup as a timeout and enters a crash loop.

```js
// BAD — crash loop if app never sends 'ready'
{ name: "my-app", wait_ready: true }

// GOOD — omit it (defaults to false)
{ name: "my-app" }
```

Only set `wait_ready: true` when you also add `process.send('ready')` to the app startup code. Source: netflix-social (2026-05).

## PM2 `--node-args` Breaks Bash-Interpreter Services

When a PM2 service uses `interpreter: "bash"` (i.e., the `script` is a `.sh` wrapper), passing `--node-args` on the command line **crashes the service immediately**. PM2 passes `--node-args` as `interpreter_args`, which are forwarded to the interpreter binary — bash in this case. Bash does not understand V8 flags like `--max-old-space-size` and exits immediately.

```bash
# BAD — crashes bash-interpreter services (passes V8 flags to bash, not node)
pm2 restart foodie --node-args="--max-old-space-size=512"

# GOOD — export NODE_OPTIONS in start.sh instead
export NODE_OPTIONS="--max-old-space-size=512"
exec node .next/standalone/server.js
```

**Affected services:** Any PM2 process with `interpreter: "bash"` in its ecosystem config (e.g., Next.js apps using `start.sh` wrappers). Node-interpreter PM2 services (the default) are not affected — `--node-args` works correctly for them.

Source: VM memory tuning session 2026-05-25 — applying `--node-args` caused immediate crashes on all bash-wrapped Next.js services (shopper, foodie, travel-assistant, finance-tracker).

## PM2 `cron_restart` Causes False Positive Crash Loop Alerts

Do **not** use `cron_restart` in a PM2 ecosystem config if you have crash-loop alerting. PM2 counts a `cron_restart`-triggered restart as an unexpected restart — incrementing the `restarts` counter and potentially triggering "restart loop" Discord alerts or monitoring dashboards.

```js
// BAD — the 5 AM restart increments the restarts counter, firing false crash alerts
module.exports = {
  apps: [{
    name: "my-service",
    max_restarts: 100,
    cron_restart: "0 5 * * *",  // triggers false positive alerts
  }]
};

// GOOD — use max_memory_restart to restart only when memory leaks accumulate
module.exports = {
  apps: [{
    name: "my-service",
    max_restarts: 10,
    max_memory_restart: "500M",  // restarts on actual leak, not on schedule
  }]
};
```

**Rule:** Use `max_memory_restart` (e.g. `500M`) instead of `cron_restart` to handle memory leaks. If scheduled daily restarts are genuinely needed, adjust the alerting threshold to account for the planned restart count.

Source: pezantTools commit `924897e` (2026-05-29) — `cron_restart: "0 5 * * *"` was triggering false positive crash loop alerts. Replaced with `max_memory_restart: "500M"` and lowered `max_restarts` from 100 to 10.

## PM2 Periodic-Exit Scripts Must Use `autorestart: false` with `cron_restart`

When a PM2 process is a **script** (runs, does work, then exits with code 0), PM2's default `autorestart: true` immediately re-fires it after every clean exit. Combined with `cron_restart`, this creates a restart loop: the cron fires, the script runs, exits 0, PM2 immediately re-fires it again — bypassing the cron schedule entirely.

**Rule:** For any PM2 process that exits on completion (data push scripts, sync jobs, batch processors), always pair `cron_restart` with `autorestart: false`:

```js
// BAD — script exits 0 after each push; PM2 re-fires immediately, ignoring cron
module.exports = {
  apps: [{
    name: "dashboard-push",
    script: "scripts/push-metrics.sh",
    cron_restart: "*/5 * * * *",
    // autorestart defaults to true → restart loop
  }]
};

// GOOD — autorestart: false lets cron_restart be the only trigger
module.exports = {
  apps: [{
    name: "dashboard-push",
    script: "scripts/push-metrics.sh",
    cron_restart: "*/5 * * * *",
    autorestart: false,  // process stays in "waiting restart" until cron fires
  }]
};
```

**Contrast with long-running services:** Always-on servers (Next.js, Express, supervisors) should keep `autorestart: true` (the default) so PM2 recovers from crashes. The `autorestart: false` pattern is only for scripts that exit normally after each run.

**Why:** finance-tracker `dashboard-push` was registering hundreds of restarts because the push script exits 0 after successfully flushing metrics, and PM2 treated every exit as a completed process eligible for immediate re-launch. Fix: commit `63b80ca` added `autorestart: false`. Also check: PM2 health allowlists (see the next section) since `autorestart: false` processes appear in `waiting restart` state between cron fires.

## PM2 Cron Scripts Must Source Secrets at Runtime, Not via PM2 Env Injection

PM2 captures environment variables **at `pm2 start` time only**. If a secret (e.g. `CRON_SECRET`, an API key) changes after the process is registered — or was not in the shell when `pm2 start` ran — every scheduled fire silently fails with 401/403 with no diagnostic output.

**Rule:** Cron shell scripts must read bearer tokens and secrets directly from `.env` at execution time:

```bash
# BAD — CRON_SECRET captured at pm2 start; stale after rotation
curl -X POST http://localhost:3001/api/cron/daily-push \
  -H "Authorization: Bearer $CRON_SECRET"

# GOOD — source from .env at run time
CRON_SECRET=$(grep '^CRON_SECRET=' /var/www/myapp/.env | cut -d= -f2-)
curl -X POST http://localhost:3001/api/cron/daily-push \
  -H "Authorization: Bearer $CRON_SECRET"
```

**Why:** `pm2 save` + `pm2 resurrect` restores process configuration but not the live env from when `pm2 start` ran. After a reboot, a credential rotation, or a fresh deploy, the env block is empty or stale for values not in `ecosystem.config.cjs`.

Source: runEvaluator `runeval-daily-push.sh` (commit `0719185`, 2026-06-07) — `CRON_SECRET` was added as a runtime grep after observing silent 401s when the secret changed between `pm2 start` and later cron fires.

## New PM2 Cron Processes Must Be Registered in All Health-Checker Allowlists

A PM2 process with a `schedule` (via `cron_restart` or an external cron shell script that calls the app) enters `waiting restart` state between fires. Health-monitoring scripts that check PM2 process states must know which processes are cron-triggered (expected to be stopped between runs) vs. always-on (unexpected if stopped).

When you add a **new** PM2 cron process, update every health-checker registry that maintains this distinction:

1. **`wsl-watchdog.sh` `CRON_PROCESSES` array** (in `~/repos/scripts/`) — processes listed here are exempt from the "waiting restart" false-positive alert. Missing entry → spurious Discord alert every time the cron process waits between fires.

2. **Discord bot's process registry** — the Discord health monitor maintains its own `CRON_PROCESSES` allowlist. Processes not listed are reported as unexpectedly stopped.

**Why:** On 2026-06-07, adding `runeval-daily-push` without updating `CRON_PROCESSES` in `wsl-watchdog.sh` generated false-positive "waiting restart" alerts for every cron cycle. Fix: commit `26875f1` added the process to the allowlist.

**Checklist for any new PM2 cron process:**
- [ ] Add to `wsl-watchdog.sh` `CRON_PROCESSES` array
- [ ] Add to Discord health monitor `CRON_PROCESSES` allowlist
- [ ] Document in the repo's `CLAUDE.md` with its cron schedule and the `CRON_PROCESSES` registration note

## Next.js `experimental.mcpServer` Causes Extra Port Binding

If `experimental: { mcpServer: true }` (or any truthy value) is set in `next.config.ts`, Next.js binds an additional port for its built-in MCP server. This causes `EADDRINUSE` when PM2 restarts overlap with that port still being held.

**Fix:** Explicitly disable it:
```ts
const nextConfig: NextConfig = {
  experimental: { mcpServer: false }
};
```

Always set `mcpServer: false` in all PM2-managed Next.js apps. Source: travel-assistant (commit 20a2611, 2026-05).

## Next.js SSR Timezone/Hydration Mismatch

Server-side rendering in Next.js formats dates with the **server's timezone** (UTC on the VM). The browser hydrates with the user's local timezone, causing hydration mismatch warnings and inconsistent timestamp display (e.g., "May 25, 2026, 12:00 AM" on server vs "May 24, 2026, 5:00 PM" in browser).

**Fix:** Use a `"use client"` component with `Intl.DateTimeFormat(undefined, options)` and `suppressHydrationWarning` on the `<time>` element. Using `undefined` as the locale defers formatting to the browser's own locale and timezone:

```tsx
"use client";

type Variant = "full" | "date" | "compact";

const OPTIONS: Record<Variant, Intl.DateTimeFormatOptions> = {
  full: { dateStyle: "medium", timeStyle: "short" },
  date: { month: "short", day: "numeric", year: "numeric" },
  compact: { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" },
};

export function LocalTimestamp({ date, variant = "full" }: { date: string; variant?: Variant }) {
  const d = new Date(date);
  return (
    <time dateTime={d.toISOString()} suppressHydrationWarning>
      {new Intl.DateTimeFormat(undefined, OPTIONS[variant]).format(d)}
    </time>
  );
}
```

**Do NOT** use `new Date().toLocaleString()` or `date-fns` formatting directly in server components or shared components — these will use server timezone. Always route timestamps through a `"use client"` wrapper.

Source: shopper, foodie, travel-assistant (commits 49da1e1, 78bbb74, d8b65c9 — 2026-05-25).

## Claude OAuth Token Refresh in Autonomous Agents

**Do NOT rely on `claude -p` to refresh OAuth tokens.** It doesn't reliably trigger refresh — tokens can expire silently. Autonomous jobs that depend on a valid Claude token then fail with cryptic auth errors.

**Correct approach:** Use the direct OAuth refresh_token grant via the platform API. Reference implementation: `~/repos/scripts/refresh-claude-token.sh` (cron every 3h, 6h-before-expiry threshold, intra-cycle retry with backoff, consecutive-failure Discord alerting, temp files for token data to avoid shell interpolation). The threshold was raised from 4h to 6h after the 2026-05-28 incident where 4 consecutive rate-limited cycles caused token expiry — see `guidance/operational-safety.md` § "OAuth Refresh Rate-Limiting".

**Why it matters:** The usage API and all autonomous agent token reads go through the credentials file. An expired token causes every quota-gating job to silently fail or report misleading usage data.

## `claude -p` vs `claude --print`: Positional Argument Trap

`-p` is NOT a clean alias for `--print`. The `-p` flag treats the **next CLI argument as a positional prompt string**, which means any flag that follows it gets consumed as prompt text instead.

```bash
# WRONG: '--model claude-sonnet-4-6' is consumed as the prompt; stdin is ignored
echo "my prompt" | claude -p --model claude-sonnet-4-6

# CORRECT: use --print (long form) when combining with other flags
echo "my prompt" | claude --print --model claude-sonnet-4-6
```

**Why it matters for automation:** Piped-stdin scripts that use `claude -p --model X` silently produce wrong output — the model flag becomes the prompt and `--model` defaults to whatever Claude picks. No error, no warning. Source: deal-scout CLAUDE.md (PR #26).

**Rule:** In any script or cron job that pipes stdin to `claude`, use `--print` (not `-p`) whenever other flags follow. Reserve `-p` for single-argument invocations like `claude -p "inline prompt"` (no piped stdin).

## Python HTTP Client Gotchas

### urllib3.Retry: Unsupported Constructor Parameters

`requests.urllib3.util.retry.Retry` does NOT accept `retry_on_connection_error` as a constructor parameter — it crashes the worker on import.

```python
retry = Retry(
    total=5, connect=3, read=3, backoff_factor=1,
    status_forcelist=[500, 502, 503, 504],
    # DO NOT: retry_on_connection_error=True  ← unsupported
)
```

Source: auto-shorts-worker PRs #39/#40.

### Localhost-First Probe for Co-Located Services

When a Python worker and its API server are on the same VM, probe for localhost at startup instead of defaulting to the public HTTPS URL (avoids DNS/SSL overhead and DNS failures in isolated networks):

```python
import socket, os

API_BASE = os.environ.get("SERVICE_API_BASE", "")
if not API_BASE:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            if s.connect_ex(('127.0.0.1', 3007)) == 0:
                API_BASE = "http://localhost:3007/service"
    except Exception:
        pass
    if not API_BASE:
        API_BASE = "https://your-vm.example.com/service"
```

Source: auto-shorts-worker transient DNS failures (2026-05).

### Python `logging.basicConfig()` Does Not Override Existing Handlers

`logging.basicConfig()` is a no-op if the root logger already has handlers (e.g., from an imported module that configured logging). The named logger you create with `getLogger(name)` may then inherit a different level than intended.

**Fix:** Always call `logger.setLevel()` explicitly after `getLogger()`:
```python
logging.basicConfig(level=logging.INFO, format="...", stream=sys.stdout, force=True)
logger = logging.getLogger("my-daemon")
logger.setLevel(logging.INFO)  # explicit — basicConfig may have been a no-op
```

Note: `force=True` (Python 3.8+) removes existing root handlers before configuring, which helps. But the explicit `setLevel` on the named logger is still the safest pattern for long-running daemons that import third-party libraries.

Source: trading-agent `error_handler.py` commit 2af1a41 (2026-05-25).

### Python `-c` Inline Scripts: Add `sys.path` Before Module Imports

When calling `python3 -c "..."` (inline script via bash substitution or heredoc), the containing directory is NOT automatically added to `sys.path`. Relative module imports fail with `ModuleNotFoundError`.

**Fix:** Insert `sys.path.insert(0, ...)` at the top of the inline script:
```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
$VENV -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from mypackage.module import func
func()
"
```

Source: trading-agent `run.sh` commit 4958408 (2026-05-25).

**When applying this fix: search ALL shell scripts for inline Python blocks.** The same import pattern may exist in multiple scripts. Use:
```bash
grep -rn 'python.*-c\|-c "' *.sh
```
Real incident: fix was applied to `run.sh` but missed `run-daytrade.sh`, requiring a follow-up commit (a0426cc, 2026-05-25).

## WSL Headless Rendering: DRI3 / LIBGL Errors

**The scenario:** A PM2 service on WSL2 that uses GPU/OpenGL-backed libraries (Chromium, Puppeteer, MediaPipe, OpenCV, PyTorch) logs DRI3 errors and may crash or degrade silently. WSL2 does not provide a DRI3-compatible GPU context for headless processes, so any library that tries to initialize GPU rendering fails at the driver layer.

**Typical error signatures:**
```
MESA: error: ZINK: vkCreateInstance failed (VK_ERROR_INCOMPATIBLE_DRIVER)
libEGL warning: MESA-LOADER: failed to open zink
dri3_open: Authentication failed
```

**Fix:** Set `LIBGL_ALWAYS_SOFTWARE=1` in the PM2 ecosystem config env block. This forces Mesa to use software (CPU) rendering via LLVMpipe, bypassing the missing GPU driver entirely:

```js
// ecosystem.config.js / ecosystem.config.cjs
env: {
  LIBGL_ALWAYS_SOFTWARE: '1',
}
```

**For MediaPipe specifically**, also force the CPU delegate in model options — MediaPipe may still attempt GPU delegate even with software rendering:

```python
from mediapipe.tasks.python import BaseOptions
base_options = BaseOptions(
    model_asset_path=str(model_path),
    delegate=BaseOptions.Delegate.CPU,  # force CPU — GPU delegate fails on WSL2
)
```

**Affected tools (non-exhaustive):** Chromium/Puppeteer, MediaPipe, OpenCV (via OpenGL backend), PyOpenGL, any MESA-dependent library.

**When to apply:** Any new PM2 service on WSL2 that imports OpenGL-dependent libraries. Add `LIBGL_ALWAYS_SOFTWARE: '1'` to the ecosystem env block by default — it has no downside on GPU-less hosts and prevents hard-to-debug silent failures.

**Source:** auto-shorts-worker commits 4828bfe/03e17e2 (MediaPipe face detector, yt-dlp rendering), browser-agent commit 35adba7 (Puppeteer screenshot failures) — 2026-05-15/29.

## Node.js 22 HTTP Gotchas

### Built-in `fetch` headersTimeout

Node.js 22's built-in `fetch` (undici) has a default **5-minute `headersTimeout`**. Requests taking longer than 5 minutes fail silently with no clear indication the timeout is the cause.

**Affected:** any long-running downstream call — Claude research queries (10-20 min), large file downloads, slow ML inference.

**Fix:** Use `http.request` with an explicit timeout:
```javascript
const http = require('http');
function longRequest(options, body, timeoutMs = 20 * 60 * 1000) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => { /* handle */ });
    req.setTimeout(timeoutMs, () => req.destroy(new Error('Timeout')));
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}
```

Source: shopper recovery scripts (commit a0caa5a, 2026-05-24).

### SSH Tunnel Bridge: Use 127.0.0.1 and Retry Transient Errors

When an app connects to a local service via an SSH reverse tunnel (e.g., the Claude bridge on port 3095), two patterns prevent tunnel flap from causing permanent job failures:

**1. Use `127.0.0.1`, not `localhost`**

`localhost` can resolve to `::1` (IPv6) while the tunnel listener is bound to `127.0.0.1` only, causing silent `ECONNREFUSED`. Hard-code the IPv4 loopback:

```typescript
const BRIDGE_URL = process.env.CLAUDE_BRIDGE_URL || "http://127.0.0.1:3095";
```

**2. Retry transient connection errors (3 attempts, 5 s delay)**

SSH tunnels flap briefly on reconnect. Errors that indicate the tunnel is temporarily down should be retried rather than immediately failing the job:

```typescript
function isTransientError(err: any): boolean {
  const msg = err.message || "";
  return (
    msg.includes("fetch failed") ||
    msg.includes("ECONNREFUSED") ||
    msg.includes("ECONNRESET") ||
    msg.includes("UND_ERR_CONNECT_TIMEOUT") ||
    msg.includes("EHOSTUNREACH") ||
    msg.includes("socket hang up")
  );
}
// 3 attempts, 5 s between retries — only for isTransientError(err)
```

Do NOT retry non-transient errors (400/401/403/503 "slots busy", 429 rate-limit) — those must fail immediately.

**Source:** foodie commit `de929dc` (2026-06-11) — tunnel flap permanently failed a query (Job #18); both the `localhost`→`127.0.0.1` switch and the retry loop were required to resolve it.

**Applies broadly:** The `isTransientError` check is the key primitive — apply the same retry guard to any internal HTTP service call that routes through a local broker or tunnel, not just the Claude bridge. Shopper's query-executor uses the same pattern for internal service calls (commit `be1d94e`, 2026-06-13).

## ID-Based Cursor Iteration for Large Dataset Processing

When a script processes all rows from a large DB table in batches, use **ID-based cursor pagination** instead of offset-based pagination (`LIMIT N OFFSET M`):

```typescript
let lastId = 0;
const BATCH_SIZE = 1000;

while (true) {
  const rows = await db.all(
    'SELECT * FROM entries WHERE id > ? ORDER BY id LIMIT ?',
    [lastId, BATCH_SIZE]
  );
  if (rows.length === 0) break;

  for (const row of rows) {
    await processRow(row);
  }
  lastId = rows[rows.length - 1].id;
}
```

**Why not offset pagination?** `LIMIT N OFFSET M` scans from the start on every batch (O(M) cost), accumulates memory across large offsets, and silently skips or re-processes rows when data changes between batches.

**Why ID-based works:** Each batch uses a WHERE clause on the indexed `id` column (`id > lastId`), giving O(1) lookup cost. The cursor state (`lastId`) is trivially resumable on crash/restart. No rows are skipped regardless of concurrent inserts.

**Batch sizing:** Keep batches small enough that peak per-batch memory stays under ~50–100 MB. The activity-tracker uses 1000 rows/batch for its entries table; very wide rows (BLOBs, large text columns) need smaller batches.

**Source:** activity-tracker commit `0a8e4a9` (2026-06-13) — OOM crash loop fixed by switching the summarizer from unbounded queries to ID-based iteration with 1000-row batches.

## Cleanup Checklist (Before Session End)

1. **Processes:** Stop any dev servers, watch commands, or background tasks you started
2. **Temp files:** Delete any scratch files you created
3. **Ports:** Verify you haven't left a rogue server bound to a port
4. **Git state:** No uncommitted changes related to your task
5. **Context:** `context.md` reflects what's running and what's not

### paste-link skill: host snippet at pezant.ca, return curl one-liner (2026-06-08)
When a snippet (heredoc, echo>>file, multi-line bash, anything with mixed quotes/backticks/escapes) is being pasted into a remote shell and gets mangled (smart-quotes, lost newlines, "syntax error near unexpected token `newline`", "Permission denied" on >>), invoke the paste-link skill instead of re-trying paste.

Why: terminal paste corruption is structural, not user error. Multiple sessions have burned cycles re-typing or working around broken pastes. The fix is to host the artifact and curl it.

How to apply: `~/.claude/skills/paste-link/host-snippet.sh <slug>` (content via stdin or --file), returns a public URL at pezant.ca/<slug>. Hand the user a one-liner like `curl -sS https://pezant.ca/<slug> >> ~/.ssh/authorized_keys && echo OK`. Skill auto-refuses content matching private-key / api_key / password / client_secret patterns. Full doc: ~/.claude/skills/paste-link/SKILL.md.

### Gemini CLI `-p` does NOT support multimodal (video/image) input (2026-06-05)

`gemini -p` (headless CLI mode with `GOOGLE_GENAI_USE_GCA=true`) treats `@filepath` references as **text only**. Binary attachments (mp4, jpg, png, etc.) are not passed as multimodal Parts — Gemini responds with "I cannot view image/video files." This is true even with `--skip-trust` and even though the Gemini API itself supports native video/image input.

**Do not plan VLM (vision/video) tasks to route through `gemini -p`.** The CLI silently fails without a clear error at the planning stage.

**Alternatives:**
- For free local image understanding: `claude -p --model haiku` natively reads images via the Read tool. ~20-30s per image batch, $0 on host auth.
- For paid native video: use the Gemini Files API directly (Node SDK or REST) with `GEMINI_API_KEY` from AI Studio. ~$0.0015/min on Flash.
- For text-only Gemini work: `gemini -p` works fine.

Source: audio-description-creator build 2026-06-05 — original architecture routed visual-understanding step through Gemini CLI (free GCA tier) but it silently produced no useful output.

### Chokidar file-watcher: denylist segment vs. substring matching (2026-06-09)

Chokidar's `ignored` function receives the **full file path**. Two types of denylist entries need different matching logic:

- **Single-segment entries** (e.g., `.state`, `node_modules`): match by checking if any path segment equals the entry → `filePath.split('/').includes(d)`
- **Multi-segment entries** (e.g., `.state/tunnel-health-state.json`): match by substring presence → `filePath.includes(d)`

Using only segment matching for all entries causes multi-segment entries to be silently skipped. If a service's own state/log files aren't excluded, the watcher creates a feedback loop: service writes state → chokidar event fires → service processes event → writes more state → repeat → OOM.

```js
const ignored = (filePath) => {
  return denylist.some(d =>
    d.includes('/') ? filePath.includes(d) : filePath.split('/').includes(d)
  );
};
```

Also always extend the default denylist to include heavy/noisy directories (`.local`, `.rustup`, `.cache`, `node_modules`) and the service's own state/DB paths. Set `kill_timeout` high enough (≥5000ms) for chokidar to close cleanly on PM2 restart — default 1.6s may cause EADDRINUSE loops.

Source: activity-tracker commits 787a863, 42f1ade, 343596d, cd920d6 (2026-06-09) — 4 commits required to resolve an OOM crash loop caused by the service watching its own `.state/` files.

### Bash `$HOSTNAME` is always set — never use `${HOSTNAME:-default}` as a bind-address guard (2026-06-06)

Bash **auto-populates `$HOSTNAME`** with the system hostname (e.g., `wordpress-7-vm` on the GCP VM). The `${HOSTNAME:-default}` substitution **never falls back** because `$HOSTNAME` is always non-empty.

**Why this matters for Node.js servers:** Next.js standalone, Vite preview, and several other Node servers read `process.env.HOSTNAME` to decide their bind address. If `$HOSTNAME` is the VM's external hostname, the server binds to the VM's IP instead of loopback, and Apache's `localhost` proxy gets connection-refused (public URL returns 503 with no useful error in app logs — server says "Ready in 0ms").

**Fix:** Force-set the bind address explicitly:
```bash
export HOSTNAME="127.0.0.1"   # GOOD — force-set, always wins
# NOT this:
export HOSTNAME=${HOSTNAME:-"0.0.0.0"}  # BAD — bash pre-fills $HOSTNAME, fallback never triggers
```

Other bash builtins similarly always populated (must not be used as `:-` defaults): `BASH_VERSION`, `PWD`, `OLDPWD`, `EUID`, `UID`, `PATH`, `SHELL`.

**Diagnostic:** If a Node service logs "listening" but Apache/curl-from-localhost gets connection-refused, run `ss -ltnp | grep <port>` and check the bind address before assuming the proxy is broken.

Source: foodie debugging 2026-06-06 — 409 historical PM2 restarts before diagnosis; `humans/start.sh` already used the correct force-set pattern.

### SQLite `.iterate()` Cleanup and File-Watcher Depth Limiting (2026-06-10)

**SQLite iterator cleanup:** Always wrap `.iterate()` in try/finally to ensure the cursor is closed even on error. An unclosed iterator holds a read transaction open, preventing WAL checkpoints and causing memory growth under high load:

```js
const iter = stmt.iterate(params);
try {
  for (const row of iter) { /* process */ }
} finally {
  try { iter.return(); } catch (_) {}
}
```

Also tune `PRAGMA cache_size` to cap SQLite's memory footprint (`PRAGMA cache_size = -32000` sets a 32 MB cap).

**File-watcher depth limiting:** Always set an explicit `depth` cap on chokidar watchers. The default (unbounded) can traverse large trees (home dir, deep node_modules) and OOM the process:

```js
chokidar.watch(paths, { depth: 2, usePolling: false })
```

`depth: 2` is usually sufficient for project file-watching. Combine with the denylist segment/substring pattern (see above) to prevent feedback loops.

Source: activity-tracker commits f455135, 9e3e3d1 (2026-06-10) — OOM crash loop resolved by adding try/finally to DB iterators, tuning cache_size, and fixing depth fallback (using `?? 2` instead of `|| 2`, since `0` is a valid depth).

### Background Queue Saturation Guards for Webhook Handlers (2026-06-10)

When a route handler spawns fire-and-forget background work (webhook processors, job dispatchers), track pending task count and return HTTP 503 when a cap is exceeded. Without this guard, burst traffic creates unbounded task queues that OOM the process:

```js
let pendingTasks = 0;
const MAX_PENDING_TASKS = 100;

app.post('/webhook', (req, res) => {
  if (pendingTasks >= MAX_PENDING_TASKS) {
    return res.status(503).json({ error: 'Queue full, retry later' });
  }
  pendingTasks++;
  processInBackground(req.body)
    .finally(() => pendingTasks--);  // MUST use .finally(), not .then()
  res.status(202).send();
});
```

Always decrement with `.finally()`, not `.then()` alone — rejected promises skip `.then()` and the count never decrements.

Source: health-hub commit 3709cf0 (2026-06-10) — background queue grew unbounded during Garmin webhook bursts, eventually crashing the process.

### SQLite `createMany` Variable Limit and Webhook Timestamp Validation (2026-06-11)

**SQLite `createMany` variable limit:** SQLite limits bind parameters per statement (~999 for older builds, up to 32766 in recent ones). Prisma's `createMany` maps each field of each record to a bind variable — for large arrays this can silently fail or throw. Chunk `createMany` calls for tables with more than a handful of fields:

```js
const CHUNK_SIZE = 100;
for (let i = 0; i < records.length; i += CHUNK_SIZE) {
  await prisma.someTable.createMany({ data: records.slice(i, i + CHUNK_SIZE) });
}
```

**Timestamp Date validation before Prisma insert:** Converting webhook numeric timestamps with `new Date(Number(raw.ts) * 1000)` produces `Invalid Date` when the value is non-numeric, null, or NaN. Prisma/LibSQL crashes on `Invalid Date` being inserted into a DateTime column. Always validate after construction:

```js
let startTime = new Date(Number(raw.startTimeInSeconds) * 1000);
if (Number.isNaN(startTime.getTime())) {
  startTime = new Date(); // fallback to current time
}
```

Source: health-hub commit c5162e6 (2026-06-11) — 20 PM2 restarts traced to these two issues during Garmin webhook bursts.

### PrismaClient Global Singleton in Next.js

Next.js can re-evaluate modules multiple times — during development hot reload and in production when bundler chunks each re-evaluate their imports. Each re-evaluation creates a new `PrismaClient` instance, exhausting DB connection pools and causing `Too many connections` or `Connection timeout` errors.

**Fix:** Always guard PrismaClient instantiation with a global variable:

```ts
declare global {
  var __prisma: PrismaClient | undefined;
}

export const prisma =
  global.__prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === "development" ? ["warn", "error"] : ["error"],
  });

global.__prisma = prisma;
```

This is the canonical pattern. `global.__prisma` persists across module re-evaluations; the `??` means only one instance is ever created per process lifetime.

**Pair with startup connection retry in production:**

```ts
if (process.env.NODE_ENV === "production") {
  const connectWithRetry = async (retries = 5, delay = 2000) => {
    for (let i = 0; i < retries; i++) {
      try {
        await prisma.$connect();
        console.log("[db] Prisma connected successfully");
        return;
      } catch (err) {
        console.error(`[db] Connection failed (attempt ${i + 1}/${retries}):`, (err as Error).message);
        if (i < retries - 1) await new Promise(r => setTimeout(r, delay));
      }
    }
    console.error("[db] All Prisma connection attempts failed. App may be unstable.");
  };
  connectWithRetry();
}
```

**Why:** humans commit `1b9df8d` (2026-06-11) — crash loop resolved by adding the global singleton guard + retry logic. All Next.js + Prisma apps in this ecosystem (humans, finance-tracker, health-hub) should use this pattern.

**Apply to:** any Next.js app that imports PrismaClient in `src/lib/db.ts` (or equivalent). If you see `warn(prisma-client) There are already 10 instances of Prisma Client actively running` in logs, the singleton is missing.

### `PrismaLibSql` Takes a Config Object, NOT a `@libsql/client` Instance

`PrismaLibSql` from `@prisma/adapter-libsql` expects a **Config object** `{ url, authToken? }` — it does NOT accept a pre-constructed `@libsql/client` instance.

```ts
// CORRECT — Config object
import { PrismaLibSql } from "@prisma/adapter-libsql";
const adapter = new PrismaLibSql({ url, authToken });

// WRONG — @libsql/client instance (causes connection errors)
import { createClient } from "@libsql/client";
const client = createClient({ url, authToken });
const adapter = new PrismaLibSql(client);  // ❌ wrong constructor signature
```

**Why this trips AI agents:** The `@libsql/client` package and `@prisma/adapter-libsql` are often imported together in docs and examples, making the instance-passing form look natural. The error message from passing an instance is not always obvious — it may manifest as a connection failure or unexpected adapter state rather than a type error.

## Express API Routes: Null-Check After DB Insert and Full try-catch Audit

### DB Write → DB Read Can Return Null

In Express routes using `better-sqlite3`, a read immediately after a write in the same handler can return `null` even after the write reports success:

```js
db.prepare('INSERT INTO instances ...').run(instanceKey, ...);
const instance = db.prepare('SELECT * FROM instances WHERE instance_key = ?').get(instanceKey);
// instance can be null (race/rollback edge case)
if (!instance) {
  return res.status(500).json({ error: 'Failed to retrieve instance after insert' });
}
res.json({ ok: true, instanceId: instance.id }); // crashes without null check above
```

Without the null guard, `instance.id` throws a TypeError and Express returns a 500 with no diagnostic — the client sees a generic error and the root cause is invisible.

**Fix:** Always null-check DB reads, even when they immediately follow a write.

### try-catch in Every Route Handler

Express 4.x does NOT automatically catch synchronous exceptions thrown inside route handlers — they bubble up as unhandled exceptions, not to the registered error handler. Every route that touches the DB, calls JSON.parse, or formats data needs an explicit try-catch:

```js
router.get('/threads/:threadId/messages', requireAuth, (req, res) => {
  try {
    const messages = db.prepare(sql).all(...params);
    res.json({ messages });
  } catch (err) {
    console.error('GET /messages error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});
```

**The cascade trigger:** once a single missing null-check or missing try-catch is found, audit ALL routes in the file — the pattern is always systemic (every route was written with the same unchecked assumptions). A partial fix leaves silent 500s in remaining routes.

Source: claudeNet commits d96d78d → 466e73f → 070ad9b (2026-06-12/13) — a single missing null-check in `formatMessage` revealed missing try-catch in 145 lines across `lib/routes-api.js`.

**Source:** health-hub commits c7681b4 → c0995b6 (2026-06-13) — a Gemini-generated fix swapped to the instance form, causing connection errors; reverted to Config object within 1 minute.

### Nullable Column Guard: `!== undefined` Instead of `||`

When a DB column can legitimately be stored as `null` (e.g. "no target linked"), using `|| default` silently clobbers stored nulls:

```js
// WRONG — clobbers stored null with the default; "row missing" and "row has null" are indistinguishable
const targetId = settings ? settings.target_instance_id || null : null;

// CORRECT — preserves stored null; only defaults when the row itself is absent
const targetId = (settings && settings.target_instance_id) !== undefined
  ? settings.target_instance_id
  : null;
```

**When it matters:** foreign-key columns, optional config values, and any "unlinked" state where `null` is a valid stored value that must round-trip correctly through the GET response.

Source: claudeNet commit 0729414 (2026-06-13) — `target_instance_id` in thread settings is legitimately `null` when no target is set; `|| null` would silently return `null` even when a non-null value was stored.

## Claude CLI `--model` Alias vs. SDK Model ID

The Claude CLI's `--model` flag takes **short aliases**, not API model IDs:

| CLI alias (correct) | API model ID (wrong for CLI) |
|---|---|
| `sonnet` | `claude-sonnet-4-6` |
| `opus` | `claude-opus-4-8` |
| `haiku` | `claude-haiku-4-5-20251001` |

Using the API ID string causes the CLI call to fail or be silently ignored:

```bash
# CORRECT
claude --print --model sonnet "your prompt"

# WRONG — claude-sonnet-4-6 is an SDK model ID, not a CLI alias
claude --print --model claude-sonnet-4-6 "your prompt"
```

**Why agents get this wrong:** the `claude-api` skill and SDK docs use full API model IDs. When an agent generates shell commands invoking `claude`, it copies the API ID format instead of the CLI short-form alias.

**When to check:** any code that calls `claude --model <name>` in a shell script or `execSync`/`spawn` call. Aliases (`sonnet`, `opus`, `haiku`) are stable; API IDs are version-suffixed and only valid for the SDK.

Source: deal-scout commit 69af5c4 (2026-06-13) — scout.js failing because `claude-sonnet-4-6` is not a valid CLI alias.

## Health Endpoint: Data Pipeline Freshness Gate

A `/health` or `/api/health` endpoint should check not only DB connectivity but whether background sync jobs have recently written. An app that is "up" but serving stale data is silently broken.

**Pattern (Next.js / TypeScript):**

```typescript
const STALE_THRESHOLD_MS = 36 * 60 * 60 * 1000; // 1.5× expected sync interval

const staleProviders = (
  await Promise.all(
    PROVIDERS.map(async (provider) => {
      const conn = await db.query.connections.findFirst({
        where: (c, { eq }) => eq(c.providerName, provider),
      });
      const stale = !conn?.lastSyncedAt ||
        Date.now() - conn.lastSyncedAt.getTime() > STALE_THRESHOLD_MS;
      return stale ? provider : null;
    })
  )
).filter(Boolean);

if (staleProviders.length > 0) {
  return NextResponse.json({ status: 'degraded', staleProviders }, { status: 503 });
}
```

**Key rules:**
- Run all provider checks via `Promise.all` (parallel, not serial)
- Return **503**, not 200 with a warning body — PM2 health checks and load balancers need the status code
- Include provider names in the response for rapid diagnosis
- Threshold = ~1.5× expected sync interval (e.g. 36h for a 24h cron)
- `lastSyncedAt IS NULL` is stale — treat it as "never synced"

Source: finance-tracker commit 7ef5c71 (2026-06-13).

### V8 Object Nullification in Batch Processing Functions (2026-06-13)

V8 does not always garbage-collect large objects that remain in scope until a function returns, even when those objects are no longer accessed. In batch-processing functions that build large aggregation maps (counts by key, duration histograms, parsed rows), explicitly set those objects to `null` after use to reduce peak RSS:

```js
export function buildSummaryFromIterator(sinceId, limit) {
  let appDurations = {};   // use `let`, not `const`
  let fileCounts = {};
  let shellCommands = [];

  for (let evt of iterateEventsSinceId(sinceId, limit)) {
    // ... process evt ...
    evt = null;  // free each row object before the next arrives
  }

  const summary = buildMarkdown(appDurations, fileCounts, shellCommands);

  // Explicitly clear large accumulators before return
  appDurations = null;
  fileCounts = null;
  shellCommands = null;

  return { summary };
}
```

**Two nullification sites:**
1. **Loop-body:** set `evt = null` after processing each row so the row object can be reclaimed before the next row is fetched.
2. **Post-accumulation:** set aggregation maps to `null` before `return`. V8 may keep them alive until the caller's frame unwinds; explicit null breaks that hold.

**When to apply:** any function that processes thousands of rows or builds large hash maps, and where the process is memory-constrained (PM2 `max_memory_restart`, containerized Node.js, etc.). Requires `let` declarations, not `const`.

Source: activity-tracker commits 6b5d813 + 18585d1 (2026-06-13) — OOM crash loop on the activity-tracker summarizer fixed by nullifying per-row `evt` references and post-run aggregation maps.

## File-Watcher Feedback Loop: Exclude Files the Service Writes To

Any service that (1) watches a directory with chokidar or a similar inotify-backed watcher AND (2) writes to a file inside that directory must explicitly exclude its own output files from watcher events. Without the exclusion, every write triggers an event, which triggers processing, which writes again — an infinite self-triggering loop that pegs CPU and floods the event log.

**Common write targets that must be excluded:**
- SQLite database files (`.db`, `.db-wal`, `.db-shm`)
- Log files (`.log`)
- Lock / state files (`.json.tmp`, `.lock`)
- Editor swap / backup files (`~` suffix, `.bak`, `.swp`)

**Chokidar pattern:**
```js
const watcher = chokidar.watch(dirs, {
  ignored: (path) => {
    if (path.includes('activity.db')) return true;   // DB + WAL + SHM
    if (path.endsWith('.log'))        return true;
    if (path.endsWith('~') || path.endsWith('.bak')) return true;
    return false;
  },
  ignorePermissionErrors: true,
  // ...
});
```

**Why substring match, not exact path:** SQLite writes three files simultaneously (`activity.db`, `activity.db-wal`, `activity.db-shm`). A substring check on the base name catches all three without enumerating each suffix.

**When to apply:** Any time a new watcher-based collector or processor is added to a service that already has a database or log file inside the watched tree. Audit the `ignored` function first — the exclusion is easy to miss when the feature is "just add a new watched directory."

Source: activity-tracker CLAUDE.md commit b39a91d (2026-06-14) — documented after summarizer OOM fix revealed the db-exclusion rule was missing from the gotchas section.

## `Promise.race` Timeout Wrapper Leaves a Dangling Timer

When implementing a timeout helper with `Promise.race`, the naïve form leaves the `setTimeout` running even after the main promise resolves. In Node.js every active timer holds a reference that delays event-loop exit and accumulates as timer-slot garbage in long-running servers.

```js
// BAD: timer fires (and logs) after the main promise already resolved
function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), ms)),
  ]);
}

// GOOD: capture the ID and clear it in .finally()
function withTimeout(promise, ms) {
  let timeoutId;
  const timeoutPromise = new Promise((_, reject) => {
    timeoutId = setTimeout(() => reject(new Error('timeout')), ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => clearTimeout(timeoutId));
}
```

**When to apply:** Any `withTimeout` / `withDeadline` helper, webhook background-task runners, or any code that uses `Promise.race` with a timeout side channel. The `.finally` guard is zero-cost on the happy path and prevents phantom timer callbacks in high-throughput services.

**Bonus: check backpressure before heavy work.** If the timeout wrapper is used inside a webhook handler that gates on queue depth, perform the 503 backpressure check BEFORE parsing the body or writing to the DB. Rejecting early avoids wasted parse/storage work when the queue is full.

Source: health-hub commit `1623f9b` (2026-06-14) — Gemini-generated fix for the Garmin webhook `withTimeout()` helper; timer leak + backpressure ordering both corrected in the same PR.

## Defensive JSON Parsing in Batch/Summarization Loops

When a batch or summarization function processes DB rows in a loop and advances a cursor or timestamp **after** the loop, a bare `JSON.parse` call will permanently stall the pipeline if any row contains corrupt or missing JSON.

**The failure mode:**
```js
// BAD — one corrupt row aborts the whole batch and the cursor never advances
export function buildSummary(events) {
  for (const evt of events) {
    const meta = JSON.parse(evt.metadata_json); // throws SyntaxError on corrupt row
    // ... build summary using meta
  }
  // ← cursor/timestamp advance happens here; never reached after throw
}

export function runSummarization(config) {
  setInterval(() => {
    try {
      const events = fetchWindow(lastSummarizeTime);
      buildSummary(events);              // throws → caught below
      lastSummarizeTime = now();         // ← never runs; same window re-fetched every tick
    } catch (err) {
      log.error(err);                    // logs every 60s but does nothing useful
    }
  }, 60_000);
}
```

Net effect: no output file is ever written again; the error repeats every tick until the corrupt row ages out of retention (up to 30 days in a 30-day window).

**Fix — defensive parse helper:**
```js
function parseMetadata(evt) {
  try {
    return JSON.parse(evt.metadata_json) ?? {};
  } catch {
    console.warn(`[summarizer] Skipping malformed metadata_json (source=${evt.source}, type=${evt.event_type})`);
    return {};
  }
}

// All call sites: meta = parseMetadata(evt);
// Existing `meta.field || default` guards already handle the empty-object case.
```

**When to apply:** Any function that:
- Processes DB rows in a loop using `JSON.parse` on a stored column, AND
- advances a cursor, timestamp, or counter AFTER the loop body.

One corrupt row in a DB column can arrive from a crashed writer, a schema migration edge case, or a race. Always guard.

Source: activity-tracker commit `a2ff5fb` (2026-06-14) — `buildSummary` stalled daily-context.md generation; fix adds `parseMetadata()` wrapper + 3 regression tests.

## SQLite `busy_timeout` Alongside WAL Mode

WAL (`journal_mode = WAL`) reduces write-write contention in SQLite, but does not prevent `SQLITE_BUSY` errors when concurrent API requests hit a read-write boundary. Without a `busy_timeout`, the first concurrent access that finds the DB busy returns an immediate error (better-sqlite3 throws synchronously), which bubbles up as a 500 to the API caller.

**Fix — add `busy_timeout` to the initialization pragma block:**
```js
function initDb() {
  db.pragma('journal_mode = WAL');
  db.pragma('synchronous = NORMAL');
  db.pragma('foreign_keys = ON');
  db.pragma('busy_timeout = 5000');  // ← wait up to 5s instead of throwing immediately
  // ...
}
```

**Why 5000ms:** High enough to survive transient request bursts without indefinitely blocking callers. If a write holds the lock for longer than 5s the service has deeper problems.

**When to apply:** Any `better-sqlite3` Express/Node.js server that serves more than one concurrent request. The symptom is sporadic 500 errors under load with no obvious error in the handler — only visible in the DB layer logs as `SQLITE_BUSY`.

Source: claudeNet commit `b7c8efb` (2026-06-13) — 500 errors under concurrent API load resolved by adding `busy_timeout` to the existing WAL pragma block.

## PrismaClient + LibSQL Adapter: Don't Pass `datasourceUrl` in the Constructor

When using `PrismaLibSql` as the Prisma adapter, the adapter already owns the database connection. Passing `datasourceUrl` as an additional constructor option to `PrismaClient` conflicts with the adapter's connection state and causes errors.

```ts
// WRONG — datasourceUrl conflicts with the adapter
const adapter = new PrismaLibSql({ url });
return new PrismaClient({ adapter, datasourceUrl: url });  // ❌

// CORRECT — adapter handles the connection; PrismaClient needs only the adapter
const adapter = new PrismaLibSql({ url });
return new PrismaClient({ adapter });  // ✓
```

**Related:** `PrismaLibSql` itself expects a **Config object** `{ url, authToken? }` — not a pre-constructed `@libsql/client` instance (documented above). These are two separate gotchas that can compound: wrong constructor argument to the adapter AND redundant datasourceUrl to PrismaClient.

## Bash Monitoring Scripts: Alert-Once-Then-Suppress via Marker State

**The problem:** A cron monitoring script that uses a file marker to track failure presence (just `touch $FAIL_MARKER`) will re-post an `@here` Discord ping on every subsequent cron cycle during a persistent failure, creating alert spam.

**The fix:** The marker must encode *whether an alert was already sent*, not just that a failure occurred. Use a two-state protocol:

```bash
if [ -f "$FAIL_MARKER" ]; then
  if [ "$(cat "$FAIL_MARKER" 2>/dev/null)" != "alerted" ]; then
    # Second consecutive failure — alert once and suppress further pings
    post_alert "Service still failing after restart" "ping"
    echo "alerted" > "$FAIL_MARKER"
    # else: already alerted, skip (persistent failure suppressed)
  fi
else
  # First failure — grace period, just mark it
  touch "$FAIL_MARKER"
fi

# On recovery, clear the marker so the next failure cycle resets
rm -f "$FAIL_MARKER"
```

**Why three states?** First failure (marker absent) = transient blip grace period, no alert. Second failure (marker has no content or empty) = escalate once. Subsequent failures (marker contains "alerted") = suppress. Recovery (service healthy) = rm marker.

**When to apply:** Any bash cron script that sends a Discord/Slack alert on failure and uses a marker file to track state. Without this, a service that stays broken for hours generates hundreds of @here pings.

Source: `scripts/bridge-auth-refresh.sh` commit `8a0436e` (2026-06-14) — fixed bridge auth refresh alerting every 10 minutes during persistent OAuth failure.

## External API 429 Handling: Exponential Backoff + Inter-Request Throttle

When calling an external REST API in a sequential loop (paginating results, fetching per-entity data), two defenses are needed:

**1. Inter-request throttle delay:** Add a fixed sleep between consecutive requests to avoid saturating rate limits before they trigger:
```js
const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// In a fetch loop:
for (const item of items) {
  await sleep(200); // 200ms between requests prevents burst triggering 429
  const res = await fetchItem(item.id);
}
```

**2. Exponential backoff on 429:** When a 429 response arrives, back off with jitter and retry:
```js
async function apiFetch(path, options, retryCount = 0) {
  const res = await rawFetch(path, options);

  if (res.status === 429 && retryCount < 5) {
    const delay = Math.pow(2, retryCount) * 1000 + Math.random() * 1000;
    console.warn(`Rate limited on ${path}. Retrying in ${Math.round(delay)}ms (attempt ${retryCount + 1})`);
    await sleep(delay);
    return apiFetch(path, options, retryCount + 1);
  }

  return res;
}
```

The `+ Math.random() * 1000` jitter prevents thundering-herd retries when multiple parallel workers all hit the limit simultaneously.

**When to apply:** Any code that calls a third-party API (Teller, Garmin, Google, etc.) in a loop. The inter-request sleep prevents rate-limit hits proactively; the 429 backoff handles them reactively when limits vary by tier or time-of-day.

Source: `finance-tracker/src/lib/teller.ts` commit `67b8ec5` (2026-06-14) — Teller API rate limiting during account sync.

## Express: `URLSearchParams(req.query)` Doesn't Handle Repeated Query Params

`new URLSearchParams(req.query)` appears correct but fails when a query parameter appears more than once in the URL (e.g. `?foo=a&foo=b`). Express parses repeated params as an **array** (`req.query.foo === ['a', 'b']`), but `URLSearchParams` constructor receives a plain object and coerces arrays to a string (`foo=a,b`) instead of two separate entries.

**Fix:** Iterate explicitly and call `.append()` for each value:
```js
// WRONG — loses multiple values for the same key
const params = new URLSearchParams(req.query);

// CORRECT — handles both scalar and array values
const params = new URLSearchParams();
for (const [key, value] of Object.entries(req.query)) {
  if (Array.isArray(value)) {
    value.forEach(v => params.append(key, v));
  } else {
    params.append(key, value);
  }
}
```

**When it matters:** Any Express route that builds a URL from `req.query` to forward to a downstream service (OAuth callbacks, search proxies, redirect handlers). A missing value here can silently break the OAuth state parameter, causing auth failures that are hard to trace.

Source: `auth-proxy/server.js` commit `47062dd` (2026-06-14) — OAuth callback proxy was corrupting state param when Google included repeated query params.

Source: health-hub commit `c09d9d0` (2026-06-14) — three-commit fix sequence (`90ec8f7` added datasourceUrl explicitly, `3796db2` corrected Config object gotcha, `c09d9d0` removed the now-exposed datasourceUrl conflict).
