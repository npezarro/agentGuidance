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

### Next.js `experimental.mcpServer` Causes Extra Port Binding

If a Next.js app has `experimental: { mcpServer: true }` (or any truthy value) in `next.config.ts`, the framework binds an additional port for its built-in MCP server at startup. This causes `EADDRINUSE` when PM2 manages the process lifecycle (PM2 restarts overlap with the extra port still being held).

**Fix:** Explicitly disable it in `next.config.ts`:

```ts
const nextConfig: NextConfig = {
  experimental: { mcpServer: false }
};
```

**Why it matters:** travel-assistant hit this in 2026-05. The `experimental.mcpServer` feature auto-enables itself in some Next.js versions when the MCP config is present. Always set it to `false` explicitly in all PM2-managed Next.js apps. Source: commit 20a2611.

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

## Claude OAuth Token Refresh in Autonomous Agents

**Do NOT rely on `claude -p` to refresh OAuth tokens.** `claude -p` does not reliably trigger token refresh — it can return successfully without refreshing, causing tokens to expire silently. Autonomous jobs (cron, PM2 services, background workers) that depend on a valid Claude token will then fail with cryptic auth errors.

**Correct approach:** Use the direct OAuth refresh_token grant via `platform.claude.com/v1/oauth/token`:

```bash
# Read refresh_token from ~/.claude/.credentials.json
# POST to https://platform.claude.com/v1/oauth/token
# with grant_type=refresh_token
# Write new tokens back to credentials file
# Fall back to claude -p only as a last resort
```

**Why it matters:** The usage API and all autonomous agent token reads go through the credentials file. If the token expires and isn't refreshed, every job that checks quota or calls Claude will silently fail or report 0% usage (misleading the gating logic into thinking it's fine to proceed).

**Reference implementation:** `~/repos/scripts/refresh-claude-token.sh` (cron every 3h, 4h-before-expiry threshold, temp files for token data to avoid shell interpolation of credentials).

## Cleanup Checklist (Before Session End)

1. **Processes:** Stop any dev servers, watch commands, or background tasks you started
2. **Temp files:** Delete any scratch files you created
3. **Ports:** Verify you haven't left a rogue server bound to a port
4. **Git state:** No uncommitted changes related to your task
5. **Context:** `context.md` reflects what's running and what's not
