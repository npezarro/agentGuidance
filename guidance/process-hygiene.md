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
2. **Graceful shutdown handler in server code:**
   ```js
   process.on('SIGTERM', () => server.close(() => process.exit(0)));
   ```
3. **Use a `start.sh` wrapper for Next.js standalone** — `next start` as the PM2 script loses process tracking. A wrapper lets PM2 signal the actual node process:
   ```bash
   #!/bin/bash
   set -a; source "$(dirname "$0")/.env"; set +a
   exec node "$(dirname "$0")/.next/standalone/server.js"
   ```

**Diagnosis:** `pm2 show <process>` with rapidly increasing restart count + `EADDRINUSE` in logs = this pattern. Source: shopper and pm-interview-practice (2026-05-15).

## Long Text Transfer

Never give the user long commands, URLs, or multi-line text to copy-paste manually. Termius and other SSH clients mangle long pastes (newline parsing, line wrapping).

**Instead:**
- **Long commands (>~80 chars):** Write to a temp script file (e.g., `/tmp/run-me.sh`), then give a short `scp` + `bash` command
- **Long URLs:** Write to a file and `scp`, or use a short redirect
- **Multi-step commands:** Break into individual short lines, never chain with `&&` for paste
- **Short commands (<80 chars):** Direct paste is fine

**Why:** Repeated incidents of mangled pastes causing failed commands. The user works in Termius SSH client which breaks on multi-line and long-string paste. Writing to files and transferring is always reliable.

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

## Next.js `experimental.mcpServer` Causes Extra Port Binding

If `experimental: { mcpServer: true }` (or any truthy value) is set in `next.config.ts`, Next.js binds an additional port for its built-in MCP server. This causes `EADDRINUSE` when PM2 restarts overlap with that port still being held.

**Fix:** Explicitly disable it:
```ts
const nextConfig: NextConfig = {
  experimental: { mcpServer: false }
};
```

Always set `mcpServer: false` in all PM2-managed Next.js apps. Source: travel-assistant (commit 20a2611, 2026-05).

## Claude OAuth Token Refresh in Autonomous Agents

**Do NOT rely on `claude -p` to refresh OAuth tokens.** It doesn't reliably trigger refresh — tokens can expire silently. Autonomous jobs that depend on a valid Claude token then fail with cryptic auth errors.

**Correct approach:** Use the direct OAuth refresh_token grant via the platform API. Reference implementation: `~/repos/scripts/refresh-claude-token.sh` (cron every 3h, 4h-before-expiry threshold, temp files for token data to avoid shell interpolation).

**Why it matters:** The usage API and all autonomous agent token reads go through the credentials file. An expired token causes every quota-gating job to silently fail or report misleading usage data.

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

## Cleanup Checklist (Before Session End)

1. **Processes:** Stop any dev servers, watch commands, or background tasks you started
2. **Temp files:** Delete any scratch files you created
3. **Ports:** Verify you haven't left a rogue server bound to a port
4. **Git state:** No uncommitted changes related to your task
5. **Context:** `context.md` reflects what's running and what's not
