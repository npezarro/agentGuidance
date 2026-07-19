<!-- Load when: spawned processes, temp files, port conflicts -->
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

### PM2 Lifecycle Traps (2026-07-16 Discord/cloud review)

Four PM2 behaviors that each caused a real silent failure; check all four when a PM2 service misbehaves around restarts or monitoring:

1. **Ecosystem config fields only register at process CREATION.** `pm2 restart` (even with the config file as argument) does not apply changed fields like `kill_timeout`, `treekill`, `shutdown_with_message`, log paths. To apply them: `pm2 delete <app> && pm2 start ecosystem.config.js --only <app> && pm2 save`. Verify what PM2 actually has registered with `pm2 jlist` (`pm2_env` keys), not what the ecosystem file says.

2. **`kill_signal` is not a PM2 option.** PM2 sends SIGINT on stop/restart/delete (global `PM2_KILL_SIGNAL` daemon env is the only override). A `kill_signal: 'SIGTERM'` key in ecosystem.config is silently ignored — design your shutdown handler around SIGINT or use `shutdown_with_message`.

3. **`shutdown_with_message: true` replaces the signal entirely.** PM2 sends the IPC string message `'shutdown'` and NO signal, then SIGKILLs after `kill_timeout`. If the app doesn't have a `process.on('message', m => m === 'shutdown' && ...)` listener, EVERY restart is a full `kill_timeout` hang ending in SIGKILL — with zero log evidence, because no signal handler ever fires. Ship the ecosystem flag and the listener in the same commit; verify with `time pm2 restart <app>` (graceful = ~1-2s, hang = exactly kill_timeout). This exact half-shipped state ran in claude-bot 2026-07-14→16.

4. **One zombie process entry poisons monitoring for the whole fleet.** A process stuck `online` with `pid: null` (process died outside PM2's view) makes PM2's pidusage batch call throw `TypeError: One of the pids provided is invalid` (~2 lines every few seconds in `~/.pm2/pm2.log`), which zeroes `monit.memory`/`cpu` for ALL apps — and silently disables every `max_memory_restart`. Diagnosis: `pm2 jlist` and look for `status: online` with no live pid. Fix: stop/delete the zombie, `pm2 save`. Ran undetected for 44 days (epic-claimer, repo deleted from under a still-registered app).

Also: after customizing `out_file`/`error_file`, the default `~/.pm2/logs/<app>-*.log` files stop updating but stay on disk — months later they read as plausible "current" logs and mislead debugging. Delete them when you move log paths, and check mtimes before trusting any log's content.

## Long Text Transfer

Never give the user long commands, URLs, or multi-line text to copy-paste manually. Termius and other SSH clients mangle long pastes (newline parsing, line wrapping).

**Instead:**
- **Long commands (>~80 chars):** Write to a temp script file (e.g., `/tmp/run-me.sh`), then give a short `scp` + `bash` command
- **Long URLs:** Write to a file and `scp`, or use a short redirect
- **Multi-step commands:** Break into individual short lines, never chain with `&&` for paste
- **Short commands (<80 chars):** Direct paste is fine

**Why:** Repeated incidents of mangled pastes causing failed commands. The user works in Termius SSH client which breaks on multi-line and long-string paste. Writing to files and transferring is always reliable.

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

## Cron Registry Reconciliation (WSL jobs registry)

The WSL crontab is GENERATED from `privateContext/jobs/registry.json`
(`jobs/generate-crontab.sh --install`). When `--install` refuses because the live
crontab has entries the registry doesn't know about, that refusal is protecting you —
never reach for `--install --force`, which silently DELETES every live-but-unregistered
job (2026-07-17: forcing would have killed the load-bearing WSL→VM token-relay crons).

Procedure:
1. Diff both directions: `diff <(crontab -l | grep -vE '^\s*(#|$)' | sort) <(./generate-crontab.sh | grep -vE '^\s*(#|$)' | sort)`.
2. For each drifted job, find the documented intent (memory, guidance, closeouts) before
   deciding direction. Drift is bidirectional: live-added jobs (new infra) AND
   deliberately-paused jobs (`#PAUSED-*` comments) both accumulate; the live crontab
   usually reflects the newest decisions.
3. Import live-only jobs into the registry as `enabled: true`; mark deliberately-paused
   registry jobs `enabled: false` with a `note` saying why + where that's documented.
4. `--install` (it writes a timestamped backup first), then verify the delta:
   `diff <(grep -vE '^\s*(#|$)' backups/<latest>) <(crontab -l | grep -vE '^\s*(#|$)')`
   must show exactly the changes you intended — nothing else activated or dropped.
5. When pausing or adding a job in future, do it in the registry, not the crontab —
   hand-edits are the source of this drift.

## Runtime & Environment Gotchas (moved)

Incident-derived patterns (Docker bind mounts / exec --user, SCP over reverse tunnels, cron cooldown + Node lock files, the four PM2 traps, Next.js mcpServer + SSR timezone, Claude OAuth refresh in autonomous agents, Python HTTP client gotchas, WSL headless rendering, Node 22 HTTP) live in `knowledgeBase/patterns/runtime-gotchas.md`. Read that page when touching those systems.

## Confirm Async Follow-Through, Not Just Dispatch (2026-07-19)

An agent that creates a PR, ticket, or any artifact meant to be picked up later is not done when the artifact exists — it's done when the artifact reaches its intended end state (merged, closed, actioned). "I created X" and "X was consumed" are different claims; only report the one you actually verified.

**Recurring pattern:** autonomousDev creates one feature PR per run, but its own closeout never re-checks whether *prior* runs' PRs actually got merged. fix-checker (a separate cron) has caught this independently at least 5 times (Runs 600, 601, 605, 608) — each time finding 1-4 fully-verified, CI-green PRs sitting stale for 2-6 days because nothing after the creating session confirmed the merge landed. One run alone found four separate repos' PRs stale simultaneously.

**Why this kept recurring across "Learning" notes without getting fixed:** the pattern was logged in `autonomousDev-private/fix-checker/logs/failures.md` three times as a "Learning" section but never promoted to a durable guidance file or a code change — each occurrence was treated as a one-off instead of a signal that the general behavior (fire-and-forget artifact creation) needed a structural fix.

**How to apply:** any runner that creates a PR/ticket/artifact for later pickup should, at the START of its next run (not just when a downstream janitor happens to notice), reconcile its own prior outputs against live state — `gh pr view <n> --json state` for every PR link in its own recent log — before creating new work. If a runner can't easily do that itself, a downstream sweep (like fix-checker) is a valid backstop, but log the sweep's cadence explicitly so staleness has a bounded worst case instead of "whenever the janitor gets to it."

## Cleanup Checklist (Before Session End)

1. **Processes:** Stop any dev servers, watch commands, or background tasks you started
2. **Temp files:** Delete any scratch files you created
3. **Ports:** Verify you haven't left a rogue server bound to a port
4. **Git state:** No uncommitted changes related to your task
5. **Context:** `context.md` reflects what's running and what's not

### paste-link skill: host snippet on the user's public site, return curl one-liner (2026-06-08)
When a snippet (heredoc, echo>>file, multi-line bash, anything with mixed quotes/backticks/escapes) is being pasted into a remote shell and gets mangled (smart-quotes, lost newlines, "syntax error near unexpected token `newline`", "Permission denied" on >>), invoke the paste-link skill instead of re-trying paste.

Why: terminal paste corruption is structural, not user error. Multiple sessions have burned cycles re-typing or working around broken pastes. The fix is to host the artifact and curl it.

How to apply: `~/.claude/skills/paste-link/host-snippet.sh <slug>` (content via stdin or --file), returns a public URL at example.com/<slug>. Hand the user a one-liner like `curl -sS https://example.com/<slug> >> ~/.ssh/authorized_keys && echo OK`. Skill auto-refuses content matching private-key / api_key / password / client_secret patterns. Full doc: ~/.claude/skills/paste-link/SKILL.md.

### Cron jobs that invoke `claude` must use an absolute binary path (2026-06-29)
Cron runs with a minimal PATH (`/usr/bin:/bin`) that does NOT include `/usr/local/bin`, where the global `claude` install lives. A cron script calling bare `claude ...` fails silently with `claude: command not found` (exit 127). On the VM this broke the host CLI auth keep-alive for ~10 days: every run failed, the OAuth refresh token expired from disuse, and the CLI started returning 401 — with no alert.

How to apply:
- Resolve the binary up front: `CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo /usr/local/bin/claude)}"` and call `"$CLAUDE_BIN"`. Works under both interactive PATH and bare cron PATH.
- `claude` is itself a node script (`#!/usr/bin/env node`), so cron also needs `node` on PATH or the CLI dies exit 127 (`env: node: No such file`) BEFORE doing anything — a probe that treats 127 as "transient" then goes blind to real outages. Prepend both bin dirs: `export PATH="$(dirname "$(command -v node 2>/dev/null || echo /usr/local/bin/node)"):$(dirname "$CLAUDE_BIN"):$PATH"`. Verify the whole script under cron conditions with `env -i PATH=/usr/bin:/bin HOME=$HOME bash your-script.sh`.
- Prefer auth keep-alives that do NOT depend on the CLI at all: refresh directly via the OAuth `refresh_token` grant (curl + python3). See `~/repos/scripts/refresh-claude-token.sh`.
- The OAuth `refresh_token` grant is rate-limited account-wide: 3+ refreshes in a few minutes trips a sustained 429 throttle (observed lasting ~2h) that blocks BOTH hosts. Never loop-retry a refresh — space attempts hours apart and let cron self-heal. A fresh `claude auth login` (authorization_code grant) is a separate bucket if you must recover sooner.
- Always pair an auth keep-alive with a probe that pages on failure (`claude-auth-probe.sh`), so a silent keep-alive failure surfaces in hours, not days.
- Refresh tokens ROTATE and are single-use: two hosts cannot share one credentials chain (whoever refreshes first breaks the other). Give each host its own `claude auth login` device session. Full write-up: `~/repos/scripts/VM-CLAUDE-AUTH.md`.
