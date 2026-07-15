<!-- Load when: self-deploy loops, restart storms, hook loops -->
# Operational Safety

Prevent feedback loops, restart storms, and cascading failures in automated systems.

## Self-Deploy Loop Prevention

**The scenario:** A Claude agent job modifies the bot that spawned it, then deploys or restarts that bot. The bot restarts, recovers the "active" job from persistence, re-attaches to the still-running process, and the cycle repeats. Each restart kills in-flight work and creates cascading failures.

**How it happens:**
1. Bot spawns a Claude job targeting the bot's own repo (e.g., discord-bot)
2. Claude finishes changes and runs `pm2 restart bot` or `vm-ops.sh deploy bot`
3. Bot restarts, loads `jobs.json`, finds the job still "active"
4. Bot re-attaches to the process (or re-queues the job)
5. The job or a recovered job triggers another restart
6. Repeat indefinitely

**Defenses (layered):**

1. **Hard guard in vm-ops.sh:** The `deploy` and `restart` verbs check `data/jobs.json` for active jobs before restarting `bot`. If jobs are active, the command is refused with an error. This is the primary barrier.

2. **Prompt-level warning in executor.js:** When a job's working directory is inside the bot repo, a `selfRestartGuard` message is prepended to the prompt telling Claude not to restart the bot. This is a soft barrier (Claude can ignore it).

3. **SIGINT handler in index.js:** The bot refuses SIGINT during startup (30s grace) and while jobs are active. PM2 sends SIGTERM to force shutdown. This prevents cascading SIGINTs from child processes.

**If a loop is already happening:**
1. Kill the stale child processes: `ps aux | grep claude | grep -v grep` then `kill <pids>`
2. Clear the persisted jobs: edit `data/jobs.json`, set `"activeJobs": []`
3. The bot will stabilize on next restart with no jobs to recover

**Rule:** Never deploy or restart a service from within a job that service spawned. Make changes, commit, push, and note that a manual restart is needed.

## Restart-Recovery Loop (Debate Jobs)

**The scenario:** A debate job is running. The auto-merger merges a PR and calls `vm-ops.sh deploy bot`. The deploy guard in vm-ops.sh sends SIGINT, but the bot ignores it (active jobs). PM2 escalates to SIGTERM, force-killing the bot. On restart, the bot loads `jobs.json`, finds the incomplete debate, re-queues it, and starts running it. Meanwhile the auto-merger retries the deploy (or another merge triggers it), creating an infinite loop of: deploy → kill → restart → recover debate → deploy.

**This is distinct from the self-deploy loop** because the deploy is triggered externally by the auto-merger, not by the job itself. The vm-ops.sh guard doesn't help because PM2 force-kills after SIGINT is ignored.

**Defenses (added 2026-03-17):**

1. **Recovery attempt limit in claudeReply.js:** Debate jobs track `recoveryAttempts` in their `debateState`. Each restart increments the counter. After 3 attempts, the job is abandoned instead of re-queued. This breaks the loop even if other defenses fail.

2. **Active-job check in auto-merger:** Before calling `vm-ops.sh deploy bot`, the auto-merger reads `data/jobs.json` and checks for active jobs. If any are active, the deploy is deferred for 60 seconds and retried. This prevents the deploy from killing active jobs in the first place.

3. **Existing vm-ops.sh guard:** Still in place as a third layer — refuses to restart if active jobs exist. But since PM2 force-kills after SIGINT, this guard only works when the bot process can actually be signaled gracefully.

**If this loop happens again:**
1. `pm2 stop bot` — halt the cycle
2. Edit `data/jobs.json` — set `"activeJobs": []` and `"queue": []`
3. `pm2 start bot` — clean restart with no recovery
4. Check error logs to identify the root cause

**Prevention rules:**
- Never merge PRs to discord-bot while long-running jobs (debates, batch queues) are active
- The auto-merger now handles this automatically, but be aware if manually deploying
- If you must deploy during an active job: `pm2 stop bot`, deploy, then `pm2 start bot` (the job will be lost, but no loop)

## Restart Storm Detection

A restart storm is when a PM2 process enters a rapid restart cycle (restarts > 5 in under 5 minutes).

**Signs:**
- `pm2 list` shows high restart count (e.g., 16+) with low uptime (seconds)
- Error logs show repeated "Bot online" messages in quick succession
- Recovery messages appearing every few seconds

**Common causes:**
- Self-deploy loop (see above)
- Crash-on-startup bug (bad config, missing env var, syntax error)
- OOM kill cycle (process exceeds `max_memory_restart` limit, restarts, loads same data, OOM again)
- Dependency failure (database down, required service unavailable)

**Response:**
1. `pm2 stop <process>` to halt the restart cycle
2. Check logs: `pm2 logs <process> --lines 50 --nostream`
3. Fix the root cause
4. `pm2 start <process>` to resume

## Bash `pipefail` + `grep -c` Silent Failure

**The scenario:** A script with `set -o pipefail` uses `grep -c 'pattern' || echo "0"` to count matches. When grep finds 0 matches, it outputs `0` AND exits code 1. Pipefail triggers the `|| echo "0"` fallback, producing `"0\n0"`. The variable becomes a two-line string that breaks `$(( ))` arithmetic silently — no error, just wrong values downstream.

**Real incident:** This exact bug caused the agentGuidance security scanner to silently fail for 13 consecutive days. It was detecting secrets in public repos daily but crashing before it could report findings via Discord or email. The state file never updated, so it rescanned the same repos with the same silent crash every run.

**Fix:** Use `grep -c 'pattern' || true` instead. `grep -c` already outputs `0` on no match — it just needs the exit code suppressed, not a fallback echo.

```bash
# WRONG — produces "0\n0" with pipefail
count=$(grep -c 'pattern' file || echo "0")

# RIGHT — outputs "0" and suppresses exit code 1
count=$(grep -c 'pattern' file || true)
```

**Rule:** In any bash script using `set -eo pipefail`, never pair `grep` (any flag) with `|| echo`. Use `|| true` to suppress the non-zero exit code.

## Headless Claude CLI: Permission Flag Requirement

**The scenario:** A script spawns `claude -p` as a subprocess (Python `subprocess.run`, Node `spawn`/`execSync`, bash pipeline). The parent process already has `--dangerously-skip-permissions`, but the subprocess is a fresh CLI invocation that doesn't inherit it. When Claude tries to use tools (WebSearch, WebFetch, Bash, etc.), it prompts for permission. With no TTY, the prompt goes to the void and the session silently fails or produces degraded output.

**Real incident (2026-04-27):** `trading-agent/collector/researcher.py` spawned Claude for deep ticker research. The main `run.sh` had `--dangerously-skip-permissions`, but `researcher.py`'s subprocess call didn't. Every research request's WebSearch calls were silently blocked, producing reports without web data.

**Rule:** Every `claude -p` invocation that runs without a TTY (cron, subprocess, server route, background job) MUST include `--dangerously-skip-permissions`. This includes:
- Python `subprocess.run([CLAUDE_BIN, "-p", "--dangerously-skip-permissions", ...])`
- Node `spawn('claude', ['-p', '--dangerously-skip-permissions', ...])`
- Bash `$CLAUDE_BIN -p --dangerously-skip-permissions`

**Detection:** The `autonomous-health` monitor scans all repos for Claude subprocess calls missing the flag (check 5: `check_permission_flags`).

**Also required: `--no-chrome`** for headless environments. Claude CLI may attempt to open a browser (e.g., for OAuth or dashboard). In headless VMs or PM2 processes, this silently hangs or errors. Add `--no-chrome` alongside `--dangerously-skip-permissions` for all automated invocations:
- `claude --print --no-chrome -p "..."`
- `$CLAUDE_BIN -p --dangerously-skip-permissions --no-chrome`

**Real incident (2026-05-15):** `auto-shorts-worker/pipeline.py` piped prompts to `claude --print -p -` without `--no-chrome`. On the headless worker, Claude attempted browser operations that failed silently.

### Gotcha: `claude -p` Eats the Next Argument as a Prompt String

When calling the Claude CLI with piped stdin **and** additional flags like `--model`, use `claude --print`, **not** `claude -p`. The `-p` flag is positional — it treats the **next CLI argument** as a literal prompt string, so `claude -p --model claude-sonnet-4-6` passes `"--model claude-sonnet-4-6"` as the prompt and ignores stdin entirely.

```bash
# WRONG — -p eats --model as the prompt; stdin is ignored
echo "$prompt" | claude -p --model claude-sonnet-4-6

# CORRECT — --print enables stdin pass-through; --model is parsed as a flag
echo "$prompt" | claude --print --model claude-sonnet-4-6
```

**Real incident (2026-06-01):** `deal-scout/scout.js` used `execSync('claude -p --model claude-sonnet-4-6', { input: prompt })`. Every eval call passed the model flag string as the prompt instead of the deal data. Fixed in commit `909f481` by switching to `claude --print`.

**Rule:** When combining piped stdin with any extra flags (`--model`, `--output-format`, etc.), always use `claude --print` as the mode flag, not `claude -p`.

### Strip CLAUDE_CODE_* Env Vars From Subprocess Invocations

> **Correction (2026-05-29):** This rule was originally written under the belief that inherited `CLAUDE_CODE_*` env vars caused the May 28 synthetic-401 incident in `fix-error-handler`. **That diagnosis was wrong.** Follow-up isolated testing (full polluted env including `CLAUDE_CODE_EXECPATH`, `CLAUDECODE=1`, and a dead `CLAUDE_CODE_SESSION_ID`) returned `is_error:false`. The true cause of those 401s was the OAuth refresh script being **rate-limited for 4 consecutive cron cycles**, leaving an expired access token. See "OAuth Refresh Rate-Limiting" below. The env-strip pattern is kept here as **defensive hygiene only** — it is not the fix for the observed incident.

**Defensive scenario:** A PM2 daemon or long-running service that was started (or restarted) from inside a Claude Code session inherits `CLAUDECODE=1` and `CLAUDE_CODE_SESSION_ID` in its env. There is no reproducible failure from this alone, but stripping the vars when spawning a `claude -p` subprocess is cheap insurance against any future CLI behavior change that might treat a nested-session-marker env as special.

**When to apply:** Long-running services (PM2 daemons, server routes) where the inherited env is opaque or stale, and where you want subprocess `claude -p` invocations to look like fresh shell calls. Not required for cron jobs that already start with a clean env.

**Pattern:** Strip `CLAUDE_CODE_*` and `CLAUDECODE` from the subprocess environment:

```python
# Python
clean_env = {k: v for k, v in os.environ.items()
             if not k.startswith("CLAUDE_CODE") and k != "CLAUDECODE"}

result = subprocess.run(
    [CLAUDE_BIN, "-p", "--dangerously-skip-permissions", ...],
    env=clean_env,
    ...
)
```

```javascript
// Node
const clean_env = Object.fromEntries(
  Object.entries(process.env).filter(([k]) => !k.startsWith('CLAUDE_CODE') && k !== 'CLAUDECODE')
);
const child = spawn(CLAUDE_BIN, ['-p', '--dangerously-skip-permissions', ...], { env: clean_env });
```

**Why PM2 captures these vars:** PM2 captures the full env at daemon start (including any `CLAUDE_CODE_*` vars from the terminal session that ran `pm2 restart`). The vars persist in the PM2 process table for the lifetime of that process slot — even across subsequent restarts — until PM2 itself is restarted from a clean environment. Whether the CLI cares about them in subprocess context is a separate question; see the correction at the top of this section.

**Also strip `NODE_CHANNEL_FD`** when launching non-Node subprocesses from a Node.js parent (e.g., a Python worker called from an Express PM2 service). Node.js IPC sets `NODE_CHANNEL_FD` in its own env; child processes that themselves use Node runtimes (such as yt-dlp's JS challenge solver) inherit this FD reference and can fail with IPC errors because the FD is already closed or invalid in the new process.

Real incident (2026-05-29): `auto-shorts-worker/pipeline.py` ran inside a Node.js PM2 parent. yt-dlp's deno/node challenge solver inherited `NODE_CHANNEL_FD` and errored with IPC channel failures. Fix: strip it in `_run()`:

```python
env = kwargs.get("env") or os.environ.copy()
if "NODE_CHANNEL_FD" in env:
    del env["NODE_CHANNEL_FD"]
kwargs["env"] = env
```

### OAuth Refresh Rate-Limiting (the real cause of the 2026-05-28 synthetic 401s)

**The scenario:** `~/repos/scripts/refresh-claude-token.sh` runs every 3h via cron and calls `https://platform.claude.com/v1/oauth/token` with a `refresh_token` grant. The endpoint is **rate-limited**, and under load can return `rate_limit_error: Rate limited. Please try again later.` for multiple consecutive cron cycles.

**Real incident (2026-05-28):** Four consecutive cycles (00:00, 03:00, 06:00, 09:00 PDT) failed with `rate_limit_error`. The access token expired ~7h into the failure window. Every daemon doing `claude -p` during that window got synthetic 401 with `model: <synthetic>` and `result: "Failed to authenticate. API Error: 401 Invalid authentication credentials"`. The CLI's `--output-format json` returns this as `is_error:false` `subtype:success` (confusingly), so the failure is not visible via standard subprocess exit codes — only by parsing the `result` field for the auth-error string. Eventually the 12:00 PDT cycle got through and the token recovered.

**Detection signal:**
- `result` field of `claude -p --output-format json` contains "Failed to authenticate" or "401 Invalid authentication credentials"
- `~/.state/claude-token-refresh.log` shows `ERROR: OAuth refresh failed: rate_limit_error` on consecutive cycles
- Daemons silently fall back to degraded mode (e.g. `fix-error-handler` falls back to direct Gemini fix without Haiku triage)

**Mitigations** (all implemented in `refresh-claude-token.sh` as of commit `ace2e0f`, 2026-05-29):
1. **6h refresh threshold** (`REFRESH_THRESHOLD_MS=21600000`) — refreshes ~3 cron cycles before expiry instead of 1.
2. **Intra-cycle retry with backoff** — up to 3 attempts per run; `rate_limit_error` backs off 60s/240s, other failures 30s.
3. **Consecutive-cycle failure counter** — stored in `~/.cache/claude-token-refresh/`. After ≥2 consecutive failures, posts a Discord alert with hours-remaining context. Counter resets on any successful or healthy cycle.

**When the consecutive-failure Discord alert fires:** The alert means the API refresh path is stuck. Do NOT wait for the next cron cycle — trigger `claude-auto-relogin.sh` (or the `/refresh-main-auth` skill). The browser OAuth path is not subject to the API rate limit and will recover the token immediately.

> **⚠ BROKEN as of 2026-07-15:** `claude-auto-relogin.sh` runs `claude auth login --claudeai`; that flag was removed in CLI v2.1.61 (exits 2 with "unknown option '--claudeai'"). Additionally, the browser-agent `eval` verb is CSP-blocked on `claude.ai` and the `cdp-eval` alternative is absent from the current browser-cli build, so the Authorize click cannot finalize the consent. Until the script is updated to use `claude setup-token`, re-auth requires a HUMAN: run `claude setup-token` on the target host, open the printed URL, Authorize, paste the code. The cron `refresh-claude-token.sh` path (OAuth refresh_token grant) is unaffected; only the full re-login automation is broken.

**Why "strip the env vars" was misdiagnosed as the fix:** The original 401 investigation happened to ship the env-strip at ~10am PDT on 2026-05-28; the OAuth refresh independently recovered at 12:00 PDT; the next observation cycle was clean and the env-strip was assumed causal. Isolated repro (full polluted env in 2026-05-29) showed the env vars alone do not produce 401. The env-strip is preserved as defensive hygiene but is not the actual fix.

**Layered defense — browser path as safety net (production validated 2026-05-29, but SEE ABOVE for broken status):** The cron `refresh-claude-token.sh` path and the browser-based `claude-auto-relogin.sh` / `claude-auth-probe.sh` path are independent recovery mechanisms. When the OAuth API endpoint is rate-limiting (the cron path fails), the browser-based path was designed to complete `claude auth login --claudeai` via the web OAuth flow — bypassing the API endpoint entirely. The two paths ran in sequence on 2026-05-29 and confirmed the design; however, the `--claudeai` flag has since been removed from the CLI and the browser automation is currently broken (see above).

**Implication:** When debugging a prolonged OAuth failure, check both paths. If the cron log shows persistent `rate_limit_error` and the access token is expired and the refresh token is still valid, the keep-alive cron will self-heal once the throttle clears — do NOT trigger `claude-auto-relogin.sh` (it will error immediately). If the refresh token itself is dead, manual `claude setup-token` is required until the script is updated.

### React SPA Hydration Race in Browser-Agent OAuth Scripts

**Symptom:** A browser-agent script clicks the OAuth Authorize button on `claude.ai`. The click reports success but nothing happens — no navigation, no callback. The same script works fine minutes later.

**Why:** React SPAs render the DOM before hydrating (wiring up event listeners). The Authorize button can be visible and selectable during this gap but fires no event when clicked. The window is typically under 2s but is reproducible on freshly-woken browser sessions.

**Real incident (2026-05-29):** `claude-auto-relogin-container.sh` failed for foodie at 00:10 PT with "callback tab not found". Shopper and travel at 00:20/00:30 PT succeeded with the same script. The fix: add `sleep 4` after locating the consent tab, then retry the click once if no callback appears within 25s.

**Pattern for OAuth automation scripts:**
```bash
# After opening the consent/authorize URL and confirming the tab exists:
sleep 4  # Let React hydrate before clicking

# Click Authorize
browser-cli click "#authorize-button" ...

# Poll for callback (up to ~25s)
for i in $(seq 1 5); do
  sleep 5
  # check if callback tab appeared ...
done

# If no callback after 25s, retry once
if [ "$callback_found" != "1" ]; then
  sleep 4
  browser-cli click "#authorize-button" ...
fi
```

**Rule:** Never do unbounded retries on a consent button. If two attempts both produce no callback, escalate via Discord alert — the problem is something other than a hydration race (rate limit, broken page, wrong selector).

### Claude CLI Binary Path on VM

The Claude CLI binary is at `/usr/bin/claude` on the VM — **not** `/usr/local/bin/claude`. Using the wrong fallback path causes silent `[Errno 2] No such file or directory` failures that drop all AI processing without any obvious error in service logs.

**Real incident (2026-05-25):** `trading-agent/error_handler.py` had `CLAUDE_BIN = "/usr/local/bin/claude"` as the hardcoded default. All Claude invocations from the error handler failed silently. Fixed in commit af0cf3c by changing to `/usr/bin/claude`.

**Rule:** When specifying a fallback path for the Claude CLI binary, always use `/usr/bin/claude`:

```python
# Python
claude_bin = os.environ.get("CLAUDE_BIN", "/usr/bin/claude")
```

```javascript
// Node
const CLAUDE_BIN = process.env.CLAUDE_BIN || '/usr/bin/claude';
```

```bash
# Bash
CLAUDE_BIN="${CLAUDE_BIN:-/usr/bin/claude}"
```

**Note:** Always prefer the `CLAUDE_BIN` env var over hardcoding so deployments with non-standard paths can override it.

## Claude CLI Rate Limit Detection in Service Wrappers

**The scenario:** A service wraps `claude -p` (e.g., via `spawn` or `execFile`) and reads stdout for the AI response. When the user hits their usage limit, Claude CLI exits with code 0 but outputs a rate limit message instead of a real response (e.g., "You've hit your limit... resets 3:50pm PT"). The service treats this as a successful result, returning garbage content to the user.

**Real incident (2026-05-15):** Shopper's Docker bridge server returned rate limit text as a "completed" buying guide. Jobs were marked successful with useless content because the bridge only checked exit code, not output content.

**Fix:** After collecting stdout from any `claude -p` subprocess, check for rate limit patterns before treating the output as valid:

```javascript
const output = stdout.trim();
if (output.match(/you've hit your limit/i) || output.match(/resets \d+:\d+[ap]m/i)) {
  // Return 429 or retry error, NOT success
  return { error: "AI at capacity", status: 429 };
}
```

**Rule:** Any service wrapping Claude CLI must detect rate limit responses and translate them to errors (HTTP 429 or equivalent). Do not rely on exit codes alone; rate limit messages arrive on stdout with exit code 0.

**Where this applies:** shopper bridge, error_handler Claude invocations, any future service that pipes prompts to `claude -p` and parses stdout.

## `set -e` Makes Post-Hoc Exit-Code Capture Dead Code

**The scenario:** A runner script uses `set -euo pipefail`, invokes `claude` (or any fallible command) as a bare statement, then tries to handle failure afterwards:

```bash
set -euo pipefail
timeout 2700 claude -p "$PROMPT" > "$LOG"   # non-zero exit kills the script HERE
EXIT_CODE=$?                                 # never reached on failure
if [ "$EXIT_CODE" -eq 124 ]; then ...        # dead code
```

Under `set -e`, any non-zero exit terminates the script before `EXIT_CODE=$?` runs. Every downstream failure path (timeout logging, Discord alerts, state writes, cost tracking) is unreachable. The same applies to command substitution: `RESULT=$(claude ...)` exits the script before the failure branch. A subtle variant: `OUT=$(cmd || true); RC=$?` — the `|| true` guarantees `RC` is always 0, silently disabling the gate that reads it.

**Real incident (found 2026-06-09):** all three autonomous runners (learnings-pass, supervisor, autonomousDev main) plus verify.sh had this bug. Zero failure alerts had ever fired across ~1,000 combined runs; a 45-minute Opus run timed out with no log entry, no state write, and a reused run ID the next day; the autonomousDev verify gate passed proven test failures for weeks.

**Fix:** capture the exit code in the same statement so `set -e` never sees the failure:

```bash
EXIT_CODE=0
timeout 2700 claude -p "$PROMPT" > "$LOG" || EXIT_CODE=$?
```

**Rule:** In any `set -e` script, a command whose failure you intend to handle must have its exit captured via `|| VAR=$?` (or run inside an `if`). Never write a bare command followed by `$?`, and never read `$?` after `|| true`. Audit: `grep -n 'EXIT_CODE=\$?\|_EXIT=\$?' <script>` — each hit must be on the same line as the command it measures.

## Hook Loop Prevention

Auto-posting hooks (WordPress, Discord) run on every Claude turn. If a hook failure triggers a retry or a new Claude session, you get an infinite loop.

**Rules:**
- Hooks must be fire-and-forget. Never retry on failure.
- Hooks must not spawn new Claude sessions without recursion guards.
- Hooks must have timeouts (10s max). A hung webhook should not block the session.
- If a hook fails, log the failure and continue. Do not abort the parent session.

### Stop Hook Safety Framework

**Full reference: `guidance/stop-hook-safety.md`** — tiered classification (Tier 1 observation, Tier 2 verification, Tier 3 Claude-invoking), shared guard library, templates, and checklists.

**Shared guard library: `hooks/lib/stop-hook-guard.sh`** — provides env var circuit breaker, PID lockfile, and per-hour rate limiter. All Tier 3 hooks must source this with `--invokes-claude`.

**Real incident (2026-05-15):** `score-session.sh` Stop hook ran the session scorer (`claude -p --model haiku`) on every session exit. The scorer's session exit re-triggered the hook. Result: 4,888 recursive sessions in one day, 199M tokens (78% of the week's usage). Fixed by adding env var guard + content pattern match. Now standardized via the guard library.

## Job Recovery Safety

When the bot recovers persisted jobs on startup:
- **PID alive:** Re-attach and monitor for completion. Do not re-execute.
- **PID dead:** Extract partial output, mark as failed, notify the user. Do not re-run automatically.
- **Debate partially complete:** Re-queue from the last completed turn, not from scratch.

**Never** automatically re-execute a failed job. The failure may have been caused by the job itself (e.g., it deployed the bot). Automatic re-execution would repeat the failure.

## Postmortem Template

When a feedback loop or restart storm occurs, document it:

```
### Incident: [Short description]
**Date:** YYYY-MM-DD
**Duration:** How long the loop ran before intervention
**Trigger:** What action started the cascade
**Mechanism:** How the loop sustained itself
**Resolution:** How the loop was broken
**Prevention:** What guard was added to prevent recurrence
```

Add the entry to the project's `context.md` under a "Known Issues" or "Incident Log" section so future sessions are aware.

## Irreversible Content Deletion

When bulk-deleting content on external platforms (YouTube, social media, cloud storage), apply strict safeguards:

1. **Gather and confirm first** — Build the full list of items to be removed and present it to the user for confirmation before deleting anything. This catches mistakes in date ranges, filters, or account selection.
2. **Restrict to safe content types** — Only auto-generated or temporary content is eligible for bulk deletion (e.g., unlisted YouTube shorts, draft posts). Never bulk-delete public, private, or manually curated content.
3. **Filter by metadata** — Apply duration, privacy status, date range, and ownership filters to exclude anything that shouldn't be touched (e.g., skip full-length videos when deleting shorts by filtering <=90s).

**Why:** Platform deletions are irreversible. A wrong date range or missing filter can wipe out manually curated content. The confirmation step and content-type restriction ensure only disposable items are at risk.

## Verify Before Asserting

Don't claim the user did something (submitted an application, sent an email, published a post) unless you can verify it through an authoritative source. The existence of prep materials, drafts, or related files does NOT confirm the action was completed.

**Why:** An agent asserted the user had applied to a role because prep materials existed on Drive. The application was never actually submitted. This led to incorrect context being shared with a referrer.

**How to verify:**
- **Applications/emails:** Check Gmail for sent confirmations
- **Blog posts:** Check WordPress or the live URL
- **Deploys:** Check PM2 status and server logs (see deployment.md § "Check the Server Before Asking")
- **Git pushes:** Check `git log origin/main` or `gh pr list`
- **Any user action:** Look for the completion artifact, not the preparation artifact

## Health Monitor Self-Exclusion

**When writing a health monitor or watchdog that scans PM2 processes, always skip the monitor's own process.**

If a health monitor watches all processes — including itself — it can trigger auto-immune loops: the monitor detects its own high restart count, attempts to fix it, restarts itself, which increments the restart count, which triggers another fix attempt.

**Pattern:**
```python
for proc in processes:
    name = proc["name"]
    if name == "fix-error-handler":  # skip self
        continue
    # ... health checks
```

**Why:** The fix-checker `error_handler.py` (2026-05-20) hit this: it scanned all PM2 processes including `fix-error-handler` itself. The dedup window increase (1h → 24h) was also needed to prevent repeated self-triggering within a single incident window.

**Rule:** Any monitoring daemon that calls `pm2 jlist` and iterates over processes must exclude its own process name from health checks.

### PM2 Log Artifacts and ANSI Codes in Error Handlers

Two related patterns that cause error handler crash loops or Discord floods when reading PM2 log output:

**1. PM2 log format artifacts in IGNORE_PATTERNS**

PM2 log output contains formatting lines that are not actual errors: separator lines (`---`), the `pm2 logs` command echo, and the handler's own prefixed log lines (e.g., `[error-handler]`). Without ignore patterns for these, the handler classifies them as errors and alerts/loops on its own output.

Always include these in `IGNORE_PATTERNS` for any PM2 log-reading error handler:
```python
IGNORE_PATTERNS = [
    r"\[error-handler\]",  # handler's own log prefix
    r"pm2 logs",           # pm2 command echo
    r"^---$",              # PM2 separator lines
]
```

**2. ANSI escape codes break dedup signatures**

PM2 sometimes emits ANSI escape sequences in log lines (color codes, cursor movement). If not stripped before computing the error signature hash, the same underlying error produces different hashes across restarts → Discord flood.

Always strip ANSI before pattern matching and dedup:
```python
import re
ANSI_ESCAPE = re.compile(r'\x1b\[[0-9;]*m')

def _strip_ansi(text: str) -> str:
    return ANSI_ESCAPE.sub('', text)

# In your log-reading loop:
clean_line = _strip_ansi(raw_line)
signature = hashlib.md5(clean_line.encode()).hexdigest()
```

Source: trading-agent `error_handler.py` PRs #67/#68 (2026-05-24).

**3. Log message prefixes that mis-trigger monitoring**

Avoid structured-looking prefixes like `SUCCESS:`, `ERROR:`, or `WARN:` in info/success log messages of a monitoring daemon. If the daemon (or a downstream watcher) pattern-matches on its own log output, a `SUCCESS:` prefix in a normal info line can look like a different error class and re-enter the alert pipeline.

```python
# BAD — "SUCCESS:" could be caught by a pattern scanner watching for status keywords
logger.info(f"SUCCESS: Claude fix complete (cost: ${cost:.4f})")

# GOOD — plain message; log level already communicates severity
logger.info(f"Claude fix complete (cost: ${cost:.4f})")
```

Source: trading-agent `error_handler.py` commit 2af1a41 → 3acbd93 (2026-05-25).

## Never inline single-quoted code in `ssh 'block'` (2026-06-23)

`ssh host 'big block ...'` wraps the whole remote command in single quotes. Any single quote INSIDE the block (e.g. JS `app.get('/path', ...)`, Python `'text/plain'`) terminates the outer quote and silently mangles the code. This shipped invalid JS to a prod server.js and crash-looped the service. Fix: write the script/patch to a LOCAL file and `scp` it, then run `ssh host 'python3 /tmp/file.py'`. Always `node --check` / syntax-validate on the VM BEFORE `pm2 restart`, and keep a `.bak` to restore.
