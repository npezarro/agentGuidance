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

## Fire-and-Forget Async Jobs Need a Startup Reaper

When a server kicks off long-running work as a fire-and-forget promise (no queue, no worker process — just `doWork().then(...)` while the HTTP response returns immediately) and records progress in a DB row (`status='pending'`), a PM2 restart (deploy, crash, OOM) kills the in-memory promise but leaves the DB row stuck in `pending` forever. Nothing ever transitions it to `completed`/`failed`, so a client polling for status waits indefinitely and no completion email/Discord notification ever fires.

**Real case (employ, commit `e11e58c`, 2026-07-14):** every AI action (role discovery, material generation) ran as an in-process fire-and-forget promise. A restart mid-job stranded a `materials` row in `pending` with no recovery path.

**Fix pattern:** on process startup (first DB open), run a reaper that marks any `pending` row older than your job's expected max duration (with margin — e.g. 2x the typical timeout) as `failed` with a retry-able message. Gate strictly on age so the reaper never touches a job the *current* process just started. This is a startup check, not a cron — it only needs to run once per process boot.

**Applies to:** any PM2-managed app that does background work in-process rather than via a real job queue (job-pipeline-style repos, employ, similar single-process Next.js/Express apps). If the app already uses a durable queue (BullMQ, a DB-backed worker table with its own heartbeat), this doesn't apply — the queue's own recovery mechanism covers it.

## Delegating Persistence to a Remote Write API Loses Data Silently (2026-08-01)

Symptom shape: a feature works perfectly while the page/tab stays open and quietly forgets everything on the next load — reported as "works in a session but isn't reliably there on next fetch." Root cause class: the only record of a mutation lives in memory, and durability is delegated to a fire-and-forget remote API call. Found in `reddit-auto-hide` v2.4:

```js
batch.forEach(id => pending.delete(id));   // dequeue FIRST
for (const id of batch) await hidePost(id); // then attempt
```

Any failure (auth not yet captured, 401, 429, timeout, navigation) dropped the item permanently while the UI still counted it as done. There was also a startup race: the drain timer fired at t=2s but the auth probe ran at t=1s/5s, so early items were dequeued with no credentials at all. This is a different failure shape than "Fire-and-Forget Async Jobs Need a Startup Reaper" above (that one is a server losing its own in-flight promise on restart); this one is a client losing its own intent because nothing durable represents "not yet done."

**Rules:**
1. Write a durable local record *before* the network call, and let the local record — not the server response — drive the UI. The feature then works offline and survives reload even if sync never succeeds.
2. Derive the work queue FROM durable state (e.g. "entries where `synced == 0`"), never as a standalone in-memory `Set`. A derived queue reconstructs itself after reload; an in-memory one silently empties.
3. Set the `synced` flag ONLY inside the success branch. Never dequeue before attempting.
4. Distinguish failure classes: 429 → pause with backoff; 401/403 → drop the cached token and re-acquire; other → increment a try counter and give up after N, keeping the local record.
5. Flush durable state on `pagehide`/`visibilitychange`, not just on a timer.
6. For two-way sync: use tombstones (`{id, deletedAt}`), not deletions — a bare delete lets another device's next push re-add the row. Make adds monotonic (re-adding an existing id must NOT bump its timestamp) or every device's periodic push resurfaces every id everywhere and sync never converges. Send `Cache-Control: no-store` on delta endpoints — behind Cloudflare a cached cursor response hands the client a stale "nextSince" and silently drops everything in between (verify with `cf-cache-status`: expect DYNAMIC/MISS, never HIT).

**Testing rule:** this bug class is invisible to in-page tests, because inside one page life the broken and correct versions look identical. The test must reload the page and assert the state is still there. Assertions must also fail on zero ("0 of 0 ids present" is not a pass).

## `x-forwarded-*` Headers Are Synthesized by Next.js Itself — a Presence Check Rejects Everything (2026-07-29)

Writing a loopback-only guard as "reject if `x-forwarded-for`/`x-forwarded-host` is present" does not work in a Next.js route handler: Next synthesizes those headers from the socket, so they're set even on a direct connection, and the guard rejects every request including legitimate direct ones. This is distinct from the `X-Forwarded-Host`/`AUTH_URL` proxy-forwarding entry in `auth-basepath.md` — that's about a value not reaching the app through an SSH tunnel; this is about the header existing when nothing forwarded it.

Observed 2026-07-29 on finance-tracker's `/api/integrations/travel-cards`: every request 404'd, including a bare `curl -v` sending no `x-forwarded-*` headers at all — proof it wasn't the client.

**Check the VALUE, not presence:** treat an absent header as loopback, and otherwise require the leftmost `X-Forwarded-For` entry to be `127.0.0.1`/`::1`/`::ffff:127.0.0.1`:
```js
function looksLoopback(req) {
  const xff = req.headers.get("x-forwarded-for");
  if (!xff) return true;
  const first = xff.split(",")[0].trim().toLowerCase();
  return first === "::1" || first.startsWith("127.") || first === "::ffff:127.0.0.1";
}
```

**Do not treat this as a security boundary** — Apache's `mod_proxy` *appends* the real client IP to any inbound `X-Forwarded-For`, so an external caller can seed a loopback address on the left and pass the check. It's defence-in-depth only; the real boundary must be a fail-closed shared secret compared with `timingSafeEqual` (for hard network enforcement, add `Require local` to an Apache `<Location>` block). Related trap in the same family: a fail-open secret check (`if (SECRET && header !== SECRET) reject`) disables auth entirely when the secret is unset, as `travel-assistant`'s `docker/bridge-server.js` did — refuse instead when the secret is missing or under 32 chars. General lesson: any request-metadata guard must be tested against both the allow and deny path before it ships; this one failed safe (deny-all), but the same error class in the other direction is a silent bypass.

## A "New Since Last Run" Digest Derived From a Seen-File Mutation Can't Be Re-Run Same-Day (2026-08-03)

Symptom: re-running a daily scanner (housing-scout, and by the same shape deal-scout/doc-digest) with `--force` posts a report with 0 new items and 0 changes even though the morning run found dozens — looks like the data source went quiet, but the source is fine.

Cause: "new" is derived as a *side effect of a write*. `trackListings()` marks each id in `data/housing-seen.json` the first time it's seen and reports exactly those ids as new — so the first run of the day CONSUMES the signal and the second run sees every id as already-known. Same shape hits price cuts (the seen-file price gets overwritten), day-over-day trend (today's snapshot is appended, so "previous" becomes today's earlier run), and off-market counts (`lastActive` is overwritten with today's active set, so nothing appears to have left).

**Fix shape:** keep recorded TIMESTAMPS as the source of truth instead of the mutation itself.
- `new` = "firstSeen within the last N hours" (N < the run interval), not `!seen[id]`
- price cuts = history entries dated within the same window, when the seen-file price already matches
- trend = compare against the last snapshot whose date != today; REPLACE today's snapshot instead of appending
- keep the prior period's id map (`prevActive`) so a re-run still has a baseline; fall back to the count identity (`prevActive + new - active`) when no prior-day map exists

**Test it:** run the job twice in a row and assert the second run's report matches the first. Any scanner whose "what's new" output depends on a file it also writes has this bug latent — audit for it the same way you'd audit for a non-idempotent migration.

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

### Parallel Bash calls race on persisted shell cwd — always cd with an absolute path explicitly (2026-07-26)
When two Bash tool calls are issued in the same message (parallel), the working directory is a single persisted shell state shared across them. If call A does `cd /repo-x && npm run build` and call B (in the same parallel batch) just runs `npm run build` assuming an earlier command's cwd still holds, the two calls can race and B executes in whatever directory A leaves the shell in — producing a false-positive 'build passed' read against the WRONG repo (observed in fix-checker run 612: a check intended for runeval returned promptlibrary's Next.js route table, silently, with no error). Caught only because the printed route names didn't match the target repo.

How to apply: in every Bash tool call that will run alongside others in a parallel batch, put an explicit `cd <absolute-path> &&` at the start of the command — never depend on a prior tool call's cd persisting when there are concurrent siblings issued this turn. Applies to any agent (fix-checker, autonomousDev, learning-agent, ad hoc sessions) doing multi-repo build/test sweeps in parallel.

### Poll-loop daemons: bound every blocking call, and run an internal heartbeat watchdog for self-restart (2026-07-29)
A capture daemon's poll loop called an OS screenshot utility (`screencapture`) via a blocking `waitUntilExit()` with no timeout. When that call hung, the entire loop froze silently — no error, no log line, no alert — for multiple hours before anyone noticed (activity-tracker, fixed commit `d950224`, "Reliability: bound blocking calls + self-healing watchdog in the capture daemon"). This is distinct from the external-monitor heartbeat pattern documented above (`operational-safety.md` "Real incident 2026-07-16" and the cron-watchdog section): that pattern detects a stall from OUTSIDE the failing process; this pattern prevents and self-heals the stall from INSIDE it.

**Rule, generalized to any poll-loop daemon/service** that shells out to a subprocess or calls a blocking OS/accessibility API (screenshot capture, AX/accessibility title lookups, `exec` of an external tool, etc.):
1. **Wrap every blocking call in the loop with a timeout.** Nothing in the loop body should be able to block indefinitely — a hang in one call must not freeze the whole daemon. (Fix here: a `runWithTimeout` helper capping subprocess calls at 5s, plus a 2s `AXUIElementSetMessagingTimeout` on the accessibility title call.)
2. **Run an internal heartbeat watchdog.** The main loop ticks a counter/timestamp every iteration; a separate watchdog thread/timer checks that the tick is still advancing. If it stalls past a threshold (here: 90s), the daemon calls `exit(1)` itself.
3. **Let the process supervisor do the restart** — launchd `KeepAlive`, PM2, or systemd — rather than trying to self-recover in-process. This turns a silent multi-hour stall into a ~90-second self-heal.

Applies to any long-running poll loop in the ecosystem that shells out or calls a blocking system API, not just this one daemon — audit for unbounded `waitUntilExit()` / `execSync` / blocking AX calls inside a loop with no surrounding timeout.
### Follow-mode log commands piped into head leak a shell process forever (2026-07-30)
A streaming log command piped into something that exits early leaks a shell process FOREVER. Found on the VM 2026-07-30: `pm2 logs trading-daytrade --lines 100 2>&1 < /dev/null | head -200` had been running for 41 days. `pm2 logs` follows by default and never exits; `head -200` closes the pipe after 200 lines; pm2 does not die on the resulting SIGPIPE, so the wrapping bash waits on it indefinitely. Two sibling orphans (21 days) and an abandoned `claude` session (15 days) were reaped in the same sweep.

Rules:

1. **Never run a follow-mode log command from an agent Bash call without disabling follow.** Use `pm2 logs <app> --nostream --lines N`. The same trap applies to `tail -f`, `journalctl -f`, `docker logs -f`, and `kubectl logs -f`: prefer the tool's own non-streaming flag over piping into `head`.

2. **If a non-streaming flag does not exist, bound it externally**: `timeout 10 <cmd> | head -N`. Piping into `head` alone is NOT sufficient, because it relies on the producer handling SIGPIPE.

3. **These leaks are invisible in normal monitoring.** Each orphan held only ~1 MB RSS, so no memory alert ever fired; they were only found by `ps -o pid,etime` during an unrelated audit. Periodically sweep for long-lived `bash -c source .../shell-snapshots/` processes, which are the signature of a leaked agent Bash call.

4. **The `claude` CLI ignores SIGTERM.** Reaping it needs a SIGTERM then SIGKILL escalation, which is the same reason `bridge-server.js` implements its own SIGTERM -> SIGKILL grace period rather than relying on spawn's `timeout` option.

### Guards on model or vendor prose must match the wording family, not one literal (2026-08-05)

When a guard parses text produced by a model, CLI, or vendor API (error messages, narration preambles, status strings), pinning it to one exact phrasing is a guard that silently expires the next time the vendor rewords.

Observed twice in two days in different shopper subsystems:
- **2026-08-03 (bridge):** Claude CLI usage-limit detection pinned to `/you've hit your limit/i`. CLI reworded to "your session limit"; the error sentence shipped as a completed guide.
- **2026-08-04 (render layer):** `extractFixReport` matched two literals ("Here's the corrected guide:", "issues to fix"). The model said "Here are the issues I found:" and "Let me output the complete improved guide now." — same content, reworded — so the narration rendered at the top of the user's buying guide. Measuring the full corpus revealed this was never one bad job: 108 of 118 stored guides (92%) began with narration that slipped past the guard since it was written.

Rules:
1. **Match the wording FAMILY.** For model/vendor prose, enumerate the family of phrasings (optional qualifiers, synonyms, tense, first vs third person). Group patterns by family so a reword lands on a neighboring variant. A guard covering one literal is a guard that expires on the next model release.
2. **Prompt instructions are a hint, not a control.** A prompt rule saying "do not start with narration" was ignored in 92% of cases. The deterministic post-processing guard is the load-bearing control; the prompt instruction is documentation of intent at best.
3. **Measure the corpus before believing a guard works.** A guard with no counter looks correct forever. When you fix or add a guard, run it over all real production data (not just fixtures) and assert both recall and that no legitimate content was incorrectly caught.
4. **Prefer a structural boundary plus a semantic signal over pure phrase matching.** The `extractFixReport` fix splits on the document's own first markdown heading (structure) once the text before it matches the narration family (semantics). This is robust to any rewording that preserves document shape.

Note: `operational-safety.md` carries the same principle scoped to CLI usage-limit strings specifically. This rule generalises it to any guard on model/vendor output.

### Scrape URLs from CLI output with a control-byte-excluding class, not `[^ ]+` (2026-08-05)

Modern CLIs emit URLs as **OSC-8 terminal hyperlinks**, whose raw pty bytes are:
```
ESC ] 8 ; ; <URL> BEL <URL> ESC ] 8 ; ; BEL
```
The URL appears **twice** — once as the escape target, once as the visible label — with control bytes (`BEL` = `\x07`, `ESC` = `\x1b`) between them and no space anywhere. A `grep -oP 'https://...[^ ]+'` matches straight through both copies, yielding a doubled URL with every query parameter appearing twice plus a trailing value polluted with `\ahttps://...`.

**Use `[^\s\x00-\x1f\x7f]+`** instead of `[^ ]+`. Excluding whitespace AND all control bytes terminates the match at the BEL before the second copy.

**Assert the shape of a parsed token immediately at the parse site.** The doubled-URL bug was silent for six nights because the script only logged the first 10 characters of the OAuth state (which looked correct), while the full value was `<state>\ahttps://claude.com/cai/...`. An OAuth state is `^[A-Za-z0-9_-]+$`; asserting that pattern right after extraction turns a 25-second misattributed downstream failure ("consent tab not found") into a one-second honest failure at the parse site.

Source: `claude-auto-relogin-container.sh` fix in scripts commit `b81676a` (2026-08-05); regression test at `test/relogin-url-parse-tests.sh` (14 TAP assertions including a proof the old pattern fails).

### `git symbolic-ref refs/remotes/origin/HEAD` exits 128 when unset — silently kills a `set -euo pipefail` script past that line (2026-08-05)

`origin/HEAD` is only populated by `git clone` (or an explicit `git remote set-head`); a checkout that came from anywhere else doesn't have it, so `git symbolic-ref refs/remotes/origin/HEAD` exits 128. Piped into `sed` under `set -euo pipefail`, `pipefail` promotes that 128 past the `sed`, and `set -e` kills the script at that exact line — nothing after it runs, for that invocation or any future one, until the line itself is fixed.

`wsl-watchdog.sh`'s stranded-branch check hit this on 2026-07-12 and stayed broken for 24 days (~6,900 runs): the VM reachability check and the entire alert-sending block sat below the broken line and never executed again. The very next line already had the correct fallback (`[[ -z "$default_branch" ]] && default_branch="main"`) — it just never got the chance to run, because `set -e` killed the script one line earlier, inside the command substitution that fed it. `2>/dev/null` on the `symbolic-ref` call hid the error message but not the exit code that `set -e` was watching.

**Nothing detected this from outside.** The script's log kept getting touched by its own `>>` redirect on every cron invocation — the script DID run, it just died partway through every time — so any mtime-based "is this cron still alive" check read it as healthy for all 24 days. The state file it should have updated was frozen at 2026-07-12, the day the check was added, and nothing was comparing that timestamp against "now." It was only caught by a purpose-built run ledger recording each run's actual exit code and expected output shape, not just whether the process touched its log.

Rules:
1. In any `set -euo pipefail` script, a `git` subcommand that can legitimately fail on some checkouts (`symbolic-ref refs/remotes/origin/HEAD`, `rev-parse --abbrev-ref @{u}` on a branch with no upstream, etc.) needs `|| true` on the command that can fail — not on a later line. A fallback written one line too late never runs.
2. A log file's mtime proves the process STARTED this cycle, not that it finished or did anything past its first few lines. Don't build "is this cron alive" on log mtime alone for a script with meaningful logic after its early lines — check the actual exit code, the log's last line, or a run ledger that records per-run outcome explicitly.

Source: a WSL cron watchdog script fix, 2026-08-05 (see `privateContext/completed-work.md` for the commit pointer).
