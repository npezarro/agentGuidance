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

## Self-Update Bootstrap Deadlock

**The scenario:** A runner script self-updates by fast-forwarding its own checkout (`git fetch && git merge --ff-only`) at the top of every run, so a merged fix takes effect on the next cron tick without a human intervening. This works perfectly for any checkout that is already at-or-past the commit that introduced the self-update call — but a checkout that was **already stale before that commit merged** can never receive it, or anything merged after it, because cron executes the exact bytes on disk, and those bytes predate the self-update logic entirely. The fix that was supposed to end silent staleness becomes permanently unreachable for the one checkout it needed to reach.

**Confirmed 2026-07-24 (learnings-pass run #1012):** `autonomousDev-private`'s local main checkout on this host was frozen at commit `6a495ac` (2026-07-23 07:12 PT). PR #39 (`884b7d0`, "runners: fast-forward local main before every run (fixes silent staleness)") merged to `origin/main` about 5.5 hours later, followed by PR #36 and PR #41. None of the three ever took effect: cron invokes `learnings-pass/run.sh` straight from the stale checkout, and that file — being from before PR #39 — contained no `runner_self_update` call, so it never fetched anything. The checkout sat 28+ hours and 3 merged PRs behind, silently, while six consecutive learning-agent runs (#1006-#1011) each noted "local checkout N commits behind, left untouched per precedent" without recognizing that N should have been shrinking to zero on its own and wasn't — the self-update mechanism had a 0% success rate because it had never executed even once on this checkout.

**This is a bootstrap-order variant of `patterns/silent-healer-failure.md`** (KB): the healer (self-update) looked like ordinary expected drift rather than a dead mechanism, because "checkout is behind" is also the normal transient state right after any merge. The tell that distinguishes "normal, will self-heal next run" from "dead, needs a manual kick" is whether the commit that *added* the self-update call is itself among the missing commits (`git merge-base --is-ancestor <self-update-commit> HEAD`, or simpler: does the checked-out file on disk contain the call at all — `grep runner_self_update <script>`).

**Fix:** One manual, one-time fast-forward unsticks it permanently — `git -C <repo> fetch origin main && git merge --ff-only origin/main` on the main checkout (not a worktree; this advances main to a commit that's already merged, it doesn't create or switch branches, so it doesn't fight the WORKTREE RULE). After that single kick, the now-current script actually contains the self-update call and keeps itself current on every future run.

**When investigating "checkout still behind" reports:** don't default to "normal, will resolve itself" — check whether the self-update commit is reachable from the stale HEAD. If it isn't, the checkout needs the manual kick above, not another cycle of waiting.

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

### CWD Hygiene and Retry Breadth for Subprocess `claude -p` Calls (2026-07-22)

Two additional hygiene rules for pipelines that shell out to `claude -p` for free-text generation:

**CWD hygiene.** When a `claude -p` subprocess runs with its working directory inside a code repo, the spawned sub-agent can explore that repo and inject meta-commentary into its output (e.g., a generated brief that narrates the relative source path it was invoked from). For free-text generation calls whose output is the primary return value, set the subprocess `cwd` to an empty/neutral directory:

```python
# Python — use a temp dir so the sub-agent sees no repo context to narrate
import tempfile
with tempfile.TemporaryDirectory() as tmp_cwd:
    result = subprocess.run([CLAUDE_BIN, "-p", "--dangerously-skip-permissions", prompt],
                            cwd=tmp_cwd, capture_output=True, text=True)
```

For calls whose output is strictly parsed (e.g. structured JSON extraction), the risk is lower but the cwd hygiene is cheap insurance.

**Retry breadth.** Retry logic for `claude -p` must retry on **ANY non-zero exit code AND on empty stdout**, not only when stderr matches "rate"/"limit". Nested `claude -p` invocations intermittently exit 1 with an entirely empty stderr (a transient fault). Code that only retries on rate-limit strings hard-fails on the first transient blip:

```python
for attempt in range(MAX_RETRIES):
    result = subprocess.run([CLAUDE_BIN, "-p", "--dangerously-skip-permissions", prompt],
                            cwd=tmp_cwd, capture_output=True, text=True)
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout  # valid response
    # retry on any non-zero exit OR empty stdout, not just rate-limit strings
    time.sleep(BASE_DELAY * (2 ** attempt))
raise RuntimeError(f"claude -p failed after {MAX_RETRIES} attempts")
```

**Real incident (job-pipeline `generate.py`, 2026-07-22):** generated brief narrated the repo source path it was invoked from (cwd was the repo root). Fix: set cwd to `tempfile.mkdtemp()` for free-text generation calls.

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

**Further mitigation (2026-07-15) — cross-host access-token relay bridge:** If the rate limit is bad enough to block BOTH the refresh grant AND new-token issuance (`setup-token`/`claude auth login` also 429) on one host, and a second host on the *same* Anthropic account has a healthy, independently-refreshing OAuth chain, bridge the two rather than waiting out the throttle blind. Access tokens are account-scoped, not host-bound, so a token minted on the healthy host works for `claude -p` calls on the throttled host. A relay cron on the healthy host periodically pushes only the current access token + expiry (never the refresh token, and never over argv — use stdin so it doesn't land in shell history or process listings) to the throttled host, merging it into that host's credentials file while leaving that host's own refresh token untouched and inert. Run the relay on a cadence comfortably shorter than the token TTL (e.g. every 2h for an ~8h token). This is a bridge, not a fix — the throttled host's own chain still needs the underlying rate limit to clear before it can refresh independently again; drop the relay once it does.

### Never Pause an Alerting/Probe Cron Alongside Its Paired Keep-Alive Cron

**The trap:** When a keep-alive/refresh cron (e.g. `refresh-claude-token.sh`) is stuck in a rate-limit storm, it's tempting to pause it AND its paired alerting/probe cron (e.g. `claude-auth-probe.sh`) together — they look like one feature, so silencing both "to stop the noise" feels natural.

**Why this is dangerous:** The probe cron's only job is to detect and page on failure. If the keep-alive cron never recovers (the throttle clears but the underlying refresh token has actually gone dead), the probe is the only thing that would catch it. Pause it too, and the failure goes fully silent.

**Real incident (2026-07-10):** Both `refresh-claude-token.sh` and `claude-auth-probe.sh` were commented out with a `#PAUSED-20260710-throttle` tag to stop an OAuth rate-limit storm. The keep-alive path never recovered — with the probe also paused, no alert fired, and VM host `claude` CLI auth was silently dead for ~5 days, 401ing every automated review cycle depending on it.

**Rule:** A probe/alarm cron that only tests cheap, already-issued-token state (e.g. `claude -p "ok"`, not an OAuth refresh grant) is typically throttle-safe and should stay running even while its paired keep-alive cron is paused. If it must be paused too, tag it with an explicit re-enable trigger (date + condition to check), not a bare `#PAUSED-<date>` — a pause with no removal trigger is a landmine that outlives the incident it was meant for.

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

## `set -e` Kills Functions Ending in a Guarded `&&`

**The scenario:** a helper function's last command is `[ condition ] && action`:

```bash
set -euo pipefail
vlog() {
  [ -n "$VERBOSE" ] && log "$*"   # returns 1 when VERBOSE is unset
}
vlog "checking..."                 # set -e exits the WHOLE script here
```

Inline, `[ cond ] && action` is safe under `set -e` (the failing test is on the left of `&&`). But as the **last command of a function**, the function's return status becomes 1, the function call itself is now a failing simple command, and `set -e` kills the script at the first call site. The failure is completely silent — no error output, exit before any later logging.

**Real incident (found 2026-07-16):** the autonomous-health monitor (WSL, 15-min cron) died at its first `vlog` call on every single run for its entire deployed life. Its log showed only `START:` lines — it never completed a check, never posted an alert, and nothing noticed, because the thing that died WAS the alerting layer. Its own cron scheduling was verifiably fine: **a heartbeat at the start of a run proves scheduling, not completion. Freshness checks must key on an end-of-run marker.**

**Fix:** `if [ -n "$VERBOSE" ]; then log "$*"; fi` (an `if` whose condition is false returns 0), or end the function with `|| true` / an explicit `return 0`.

**Rule:** in `set -e` scripts, never end a function body with a bare `[ cond ] && cmd`.

## Cron Output Redirects Into Root-Owned Dirs Die Silently

**The scenario:** a non-root crontab line redirects into `/var/log/`:

```
*/5 * * * * $HOME/bin/watchdog.sh >> /var/log/watchdog.log 2>&1
```

The shell opens the redirect target BEFORE running the command. If the dir is not writable by the cron user and the file doesn't exist, the open fails and **the command never runs at all** — every occurrence, forever, with no trace beyond an unread cron mail. The trap is asymmetric: if the log file already exists (created earlier when perms allowed, or pre-touched by root), appending works — so some `/var/log` crons keep working while their siblings are dead, which defeats "the other one works, so the pattern is fine" reasoning.

**Real incident (found 2026-07-16):** `/var/log` on the VM is root-owned 755; 9 of 11 user cron entries redirecting there were dead — both PM2 watchdogs, the uptime monitor, the error aggregator, the restart alerter, the guidance sync, the daily bot restart, db-guardian (never ran once), and the Discord bot state backup (last artifact 4 months old). The 2 survivors had pre-existing log files. One dead cron had been individually "fixed" on 2026-06-02 by pre-creating its log file — the instance was patched, the class was not.

**Rules:**
- Non-root cron output goes to a user-owned dir (`~/logs/cron/` on the VM); never redirect cron output into `/var/log` as a non-root user.
- When you find one broken cron redirect, audit the whole crontab for the class: `crontab -l | grep '/var/log'`.
- Every watchdog/monitor needs periodic end-to-end verification: does its log show a run **completing** (not just starting) within the last interval, and can it still deliver its alert? A monitoring stack in which every layer dies silently (this incident: VM watchdog crons dead + WSL health monitor dead + PM2 pidusage monitoring poisoned, simultaneously) is the default failure mode, not the exception.

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

## Concurrent Sessions in One Checkout

Moved. This topic had grown three homes in one afternoon (this section, `guidance/concurrent-sessions.md`, and a KB page), written by three sessions that could not see each other — which is the problem itself, in miniature.

Canonical guidance: **`guidance/concurrent-sessions.md`** — worktree per session (Problem A: shared tree), real locks for singletons (Problem B), the `claim-guard.sh` backstop with its behavior table and `~/.claude/settings.json` registration block, and the diagnostic order when something keeps reverting.

Cross-repo view: KB `patterns/shared-checkout-concurrent-sessions.md`.

## Job Recovery Safety

When the bot recovers persisted jobs on startup:
- **PID alive:** Re-attach and monitor for completion. Do not re-execute.
- **PID dead:** Extract partial output, mark as failed, notify the user. Do not re-run automatically.
- **Debate partially complete:** Re-queue from the last completed turn, not from scratch.

**Never** automatically re-execute a failed job. The failure may have been caused by the job itself (e.g., it deployed the bot). Automatic re-execution would repeat the failure.

**Any recovery cron that runs concurrently with the primary job path must compare-and-swap on status, and its stale-timer must exceed the primary path's own timeout.** Shopper/foodie/travel-assistant all run a periodic `run-recovery.js` cron that re-executes jobs it believes are stuck. Two invariants keep it from overwriting a good result the main request path already produced (symptom: a job the user saw succeed later flips to `failed` with a recovery-origin error like "Request timed out" or "Response too short"):
1. **Compare-and-swap on every write.** Both the success and failure `UPDATE`s must carry `AND status = 'pending'`, and notifications must be skipped when the guarded write reports `changes === 0`. Without the guard, a late timeout/short-response from the duplicate recovery call overwrites the main path's completed result.
2. **Stale threshold must exceed the primary executor's own timeout.** If the main path times out a job at 20 minutes, the recovery cron's stale-pending threshold must be set higher (e.g. 25 minutes) — otherwise recovery grabs a job the main path is still legitimately working on. Keep the two values in sync whenever either changes.

**Why:** hit identically in three separate apps (shopper, foodie, travel-assistant) — same `run-recovery.js` pattern, same missing CAS guard, same too-tight stale threshold, same user-visible symptom (a completed search silently flips to failed minutes later). Any writer that can run concurrently with a primary job path needs this same pair of guards.

**A different question — "is this job orphaned at all?" — should be answered with an owner token + heartbeat, not a `created_at` age threshold.** Age only proves the row is old, not that its owning process is dead, which is what forces the stale-threshold tuning above in the first place: a job orphaned 1 minute in still sits visibly broken until the threshold elapses. Record `worker_id` (a per-boot UUID) + `heartbeat_at` (refreshed every ~30s while the job runs) instead — a pending row carrying a different or absent `worker_id` is unambiguously orphaned, no age heuristic needed. Implemented in `travel-assistant/src/lib/job-tracker.ts`; shopper/foodie still use pure age-based recovery and would benefit from the same schema. Full pattern: `knowledgeBase/patterns/age-is-not-liveness.md`.

## Unattended Jobs That Take Irreversible External Actions

A cron job that spends money, sends a message, cancels a subscription, or files
something is not a normal cron job: a bug does not just fail, it does the wrong
thing to the outside world, and nobody is watching when it happens. Five
requirements, all of them cheap:

1. **Gate on identity, not just success.** Before the irreversible step, assert
   the thing in front of you is the thing you meant: expected item/recipient
   name, expected quantity. Refuse and report on mismatch. A checkout page that
   loads fine is not evidence it holds the right cart.
2. **Cap the magnitude.** A hard ceiling (`MAX_TOTAL`) turns a pricing change,
   a currency bug, or a duplicated line item into a refusal instead of a charge.
3. **Idempotency guard.** Keep a per-period state file (`~/.state/<job>-last-*.json`)
   recording the period already completed, and check it first. Without this, a
   manual re-run, a retry, or two overlapping schedules double-execute. This is
   the single highest-value guard, because retries are otherwise unsafe to add.
4. **A `--dry-run` that stops immediately before the irreversible call** and
   exercises everything up to it. This is what makes the job testable at all;
   without it the only test is doing the thing for real.
5. **Report every outcome, including failure.** Silence must never be the
   success signal. Route through `~/repos/scripts/send-alert-email.sh` (or
   Discord) on success, failure, AND skip.

**Retry windows: separate transient blockers from real failures.** A job that
depends on something ambient (the browser being open, a VPN, the laptop being
awake) cannot be scheduled at one fixed time and called reliable. Sweep a window
instead, but only if the alerting is retry-aware, or an outage becomes a dozen
identical emails and the next real alert gets ignored:

- **Transient** (dependency not ready yet, later attempt may clear it): log,
  stay silent during the window.
- **Real** (failed gate, missing credential, unparseable confirmation): email
  immediately; a human is needed and more attempts will not help.
- **Already done** (idempotency guard fired): silent. This is the steady state.
- **Close the window with one `--final` run** that alarms if the period never
  completed. That single email is the "we missed it" signal, and it fires once.

Reference implementation:
`privateContext/recurring-tasks/scripts/staples-giftcard-buy.py` (all five, plus
`--retry`/`--final`); siblings in the same directory: `smbx-withdraw.sh`,
`peloton-cancel.sh`.

**Related:** if the job drives a browser, it also inherits
`guidance/deployment.md`'s verify-before-claiming rule — parse the confirmation
for a real identifier (an order number), never trust that the click "worked".

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

**Same principle for unattended age-based prune/retention scripts (backups, logs, caches): write them as an ALLOWLIST of patterns eligible for deletion, never a DENYLIST of patterns to exclude.** A denylist ("delete anything past N days except these patterns") opts every future/unanticipated file type into deletion by default. An offsite WordPress backup script did exactly this — `rclone delete --min-age 45d --exclude "*-uploads.zip" --exclude "*-themes.zip" ...` — and its first run deleted the only offsite copy of a one-time full-content backup, because that file was simply never added to the exclude list. Inverted to `--include` patterns matching only known rotating artifacts (nightly `*.db.gz`/`*.sql.gz` dumps); anything unrecognized is now retained by default. The failure mode becomes "the remote grows and disk-guard notices" instead of "a restore path silently disappears" — always prefer the prune bug that fails loud (wasted space) over the one that fails silent (lost data).

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

## A "reverting" deployed artifact may be a second concurrent session, not cache or cron (2026-07-17)

When multiple agent sessions run in the same home directory (common under `--dangerously-skip-permissions`), nothing prevents two of them from owning the same deploy target or repo file. If a deployed file "keeps reverting to the old version" after you redeploy it, suspect a **second live session writing the same path** before jumping to caching or a stray cron job. This is a distinct failure mode from the `git add -A` staging collision documented above (that one corrupts a commit at staging time; this one is two processes racing on the same deploy target repeatedly, well after either committed).

**Diagnostic order (cheapest signal first):**
1. `stat` the origin file's mtime/size against your own deploy time — if it changed AFTER you deployed, someone else wrote it.
2. Check the edge cache header (`curl -sI ... | grep cf-cache-status`) — `DYNAMIC`/`no-store` rules out Cloudflare as the cause.
3. `git log --format='%h %ci %s' -- <path>` — look for a foreign commit between yours and the current state. A `git add -A` closeout commit is a common clobberer.
4. `ps -eo pid,etimes,cmd | grep claude`, then grep the most-recently-modified transcripts under `~/.claude/projects/<proj>/*.jsonl` for the path in question — the session with recent writes to it is the culprit.
5. Fix by coordinating targets (point the other session at a different path), not by re-deploying repeatedly to "win" the race. Killing a live interactive session is destructive — ask first, don't just kill it.

Source: two concurrent sessions both deploying to the same static-site `index.html` target on `example.com`, one repeatedly clobbering the other's report-feed redesign with a stale finance-dashboard rebuild (2026-07-17).

## Cron-Triggered Runners Silently Execute Stale Code After a PR Merges (2026-07-21)

A cron job that operates on a local git checkout (reads its own prompt template, sources its own lib functions, scans other repos) has no reason to ever be behind — but nothing fast-forwards that checkout unless something explicitly does. A `git pull`/`fetch`+`merge --ff-only` is not implied by "the PR merged." This is easy to miss because the staging side (worktree-based PR flow, so the main checkout stays untouched for concurrent sessions' hooks) actively *avoids* touching the checkout, and there's no separate step that ever brings it forward.

**Confirmed:** a learning-agent run (#988) found its own generated mission file still exhibited a bug (S149, `{{PLACEHOLDER}}` corruption in `${var//pattern/replacement}` substitutions) whose fix had merged to `origin/main` **40 minutes earlier** (`autonomousDev-private` PR #38). The local checkout the cron job actually executes from was still 1 commit behind — the merge had happened on GitHub, but nothing had ever pulled it down locally. The same gap existed independently in a second pipeline (`agentRuntime/security-scanner`, 3 cron scripts, no shared lib at all).

**Fix pattern:** at the very top of each runner (right after its lock is acquired, before reading any prompt template or repo content), fetch + fast-forward-merge the runner's own repo:
```bash
_branch=$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || echo "")
if [ "$_branch" = "main" ] || [ "$_branch" = "master" ]; then
  git -C "$REPO_DIR" fetch origin "$_branch" --quiet 2>/dev/null \
    && git -C "$REPO_DIR" merge --ff-only "origin/$_branch" --quiet 2>/dev/null \
    || log "WARN: self-update failed for $REPO_DIR — running possibly-stale code"
fi
```
Fail-open (log a warning, never abort the run) — a transient fetch failure shouldn't turn a cron job into a hard outage. `--ff-only` is safe alongside uncommitted local state changes (runner-managed `state.json`/log files) since it only advances the branch pointer when there's no real divergence.

**Applies beyond the runner's own code:** any pipeline that reads a SEPARATE repo's content (a different repo's `CLAUDE.md`, a shared guidance dir) to build a prompt or stage a worktree branch has the same exposure on that repo's checkout too — a stale read either re-proposes already-merged content or forks a new branch from a stale base (a likely contributor to past merge-conflict cleanup in this very pipeline's own PR history).

Source: `autonomousDev-private` PR #39 and `agentRuntime` PR #2 (both 2026-07-21) — see each repo's `lib/runner-lib.sh` (or inline copy) for the `runner_self_update`/equivalent implementation.

## Autonomous Runners Strand Their Checkout on a Merged PR Branch (2026-07-21, confirmed recurring 2026-07-27)

Distinct from the staleness bug above: this is about a runner's checkout being left on the WRONG branch entirely, not just behind on the right one. When a cron-triggered agent stages a fix by checking out a working branch in its OWN repo checkout (`git checkout -b claude/auto-*` or `gemini/fix-*`, commit, push, open a PR) and that PR later merges, nothing ever returns the checkout to `main`/`master`. The next run's `SessionStart` hooks and any lib code reading "the current branch" execute against a dead feature branch instead of main — silently, since the branch still exists locally and `git status` shows a clean tree.

**Confirmed 3 separate runners with this gap, so far:** `autonomousDev-private/run.sh` and `fix-checker/run-gemini.sh` (learning-agent run #1003 found 17 repos stranded this way, some since April 2026) and, newly confirmed 2026-07-27, `autonomousDev/claudemd-audit/run.sh` (`pezantTools` checkout left on `claude/claudemd-audit-14` for a full day after PR #143 merged — recovered by fast-forwarding to `origin/main` and deleting the stale local branch once a content diff confirmed nothing unique was on it). Only `learnings-pass/prompt.md` currently carries an explicit WORKTREE RULE; the other runner prompts don't instruct the agent to return to the default branch after pushing.

**Fix pattern:** the runner's prompt must never let the agent `git checkout` a work branch in its own main checkout at all — stage all edits in a throwaway worktree (`git -C <repo> worktree add /tmp/wt-<repo> -b claude/<branch>`, edit/commit/push/PR from there, then `git -C <repo> worktree remove /tmp/wt-<repo>`), the same rule `learnings-pass/prompt.md` already follows. This avoids the stranding failure mode entirely rather than trying to detect and recover from it after the fact. Recovery for an already-stranded checkout: confirm the PR is merged (`gh pr view <n> --json state,mergedAt`), diff the branch's unique commits against `origin/<default-branch>` to confirm no content would be lost (squash-merges change the commit hash, so compare file diffs, not `git merge-base --is-ancestor`), then `git checkout <default-branch> && git merge --ff-only origin/<default-branch>` and `git branch -D` the stale local branch.

**Applies to any new automation repo** created without copying the worktree-staging pattern — it isn't specific to autonomousDev-private's runners. Full audit + suggested prompt fix (not applied directly — out of scope for a doc-capture pass to edit another agent's prompt): `autonomousDev-private/learnings-pass/suggestions.md` S225 and S229.
### Audit Claude Code version on every host and pin fan-out/search defaults before upgrading (2026-07-29)
Claude Code version drift silently keeps already-fixed reliability bugs in play, and headless hosts drift worst because nobody watches their startup banner. Audit 2026-07-29: the local WSL install was 19 versions behind (2.1.201) and the GCP VM host 8 behind (2.1.212) against 2.1.220, so both were still exposed to v2.1.217 (MCP truncated tool outputs kept the full untruncated result in memory for the rest of the session), v2.1.214 (stream-json output truncated at exit for slow-reading SDK/pipeline consumers, which makes a headless job report success with the tail of its response missing), and v2.1.216 (quadratic message-normalization stalls in long sessions).

Rules:

1. Check `claude --version` against `npm view @anthropic-ai/claude-code version` on EVERY host that runs claude (WSL, VM host, Docker bridges), not just the interactive one.

2. Pin fan-out and search behavior BEFORE upgrading, because upgrades change defaults underneath you: v2.1.219 raised default nested-subagent spawn depth from 1 to 3, and v2.1.213 added a session-wide 200-call WebSearch cap. Set `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` and `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION` explicitly so an upgrade never changes spend or research depth implicitly. Implicit depth-3 nesting can outrun what the usage gate reasons about, since the gate models the fan-out the top-level session controls.

3. Set `fallbackModel` (array, max 3 entries, does NOT merge across settings files) on every host running headless runners. Without it a runner hard-fails when its primary model is unavailable or overloaded: the silent-healer failure class from ESSENTIAL rule 8.

4. Verifying a settings change means launching the CLI and getting a reply, not just parsing the JSON. An unsupported or misspelled settings key is accepted silently and does nothing. Corollary: env vars introduced in a version NEWER than the installed CLI are inert until the upgrade lands, so setting them is upgrade-preparation, not an active change.

5. `propagate-learning.sh --guidance-file` resolves from the repo root, so pass `guidance/<file>.md`, not the bare filename. A bare filename silently SKIPs the guidance destination.

6. **Containerized Claude drifts worst, and the host version tells you nothing about it.** Bridge Dockerfiles install with an UNPINNED `RUN npm install -g @anthropic-ai/claude-code`, so each image freezes whatever was latest at build time and never moves again. Audited 2026-07-29: eight live bridges sat at 2.1.145, 2.1.177, and 2.1.196 while the hosts were on 2.1.201/2.1.212.

   **Match the CVE-style fix list to how the consumer actually invokes claude before calling drift urgent.** First pass of this audit asserted the bridges were exposed to the 2.1.214 stream-json exit-truncation bug, the 2.1.217 MCP-output memory leak, and 2.1.216 long-session stalls. Reading `bridge-server.js` refuted all three: the bridges spawn `claude -p --allowedTools ...` and accumulate PLAIN stdout (no `--output-format stream-json`), attach NO MCP servers, and run one-shot per request rather than long sessions. Version drift is real, but a fix only matters if the invocation path touches it. Check the spawn arguments, not the version number alone.

   Two consequences that do hold:
   - **Pin the version in the Dockerfile** (`@anthropic-ai/claude-code@<version>`). Unpinned means every rebuild is a silent, unreviewed upgrade that can change defaults (see rule 2), and builds are not reproducible.
   - **Rebuild on a cadence, not on demand.** An unpinned image that is never rebuilt is the worst of both worlds: frozen on an old version AND guaranteed to jump many versions at once whenever it finally is rebuilt. Enumerate with `docker exec <container> claude --version` per container.

### Unpinned Docker installs make rebuilds a silent no-op; docker exec probes claude as root and false-alarms on auth (2026-07-30)
Rebuilding the 8 bridge containers to 2.1.220 (2026-07-30) surfaced two traps that make a rebuild look successful when it did nothing, and make a working bridge look broken.

1. **An UNPINNED install plus Docker layer cache means `docker compose build` is a silent no-op.** travel-bridge rebuilt cleanly and came back still on 2.1.145. Its `RUN npm install -g @anthropic-ai/claude-code` line was byte-identical to the previous build, so Docker reused the cached layer and never re-ran npm. The other seven bridges upgraded ONLY because pinning the version changed that line and busted the cache. So an unpinned image is doubly bad: it freezes at build-day latest AND resists the rebuild you would use to fix it. Either pin the version (preferred, and the cache-bust is a feature) or build with `--no-cache`. Always assert the version INSIDE the container after a rebuild (`docker exec <c> claude --version`); never infer success from a clean build log.

2. **`docker exec <container> claude -p ...` runs as ROOT and reports "Not logged in", even when the bridge is perfectly authenticated.** Credentials live at `/home/node/.claude/.credentials.json`, but root's HOME is `/root`, so the CLI finds nothing. This looks exactly like a rebuild wiping credentials and will trigger a false rollback. Probe as the service user instead: `docker exec -u node -e HOME=/home/node <c> claude -p "..."`. Confirm any suspected breakage against an un-rebuilt container as a control before acting.

3. **`auth=pending` on `/health` immediately after a rebuild is expected, not a failure.** `bridge-server.js` sets `AUTH_CHECK_INTERVAL = 30 * 60 * 1000` and the first check lands roughly 60s after start. Wait for `authCheckedSecondsAgo` to be populated before judging.

Credentials survive a rebuild: they live in a named volume (e.g. `shopper_claude-auth` -> `/home/node/.claude`), not in the image, so `docker compose build && up -d` preserves them and no re-OAuth is needed.

### sandbox.network.strictAllowlist is not usable in Docker bridges or on the WSL host (2026-07-30)
Investigated 2026-07-30 and CLOSED as not-applicable. This corrects an earlier recommendation from the same session that called it "the highest-value remaining security item."

**The bridges cannot use it.** The Claude Code sandbox is enforced by bubblewrap, which requires unprivileged user namespaces. Inside the bridge containers `bwrap` fails with `Creating new namespace failed: Operation not permitted`, including the weaker variant that binds the existing `/proc`. The host kernel is NOT the blocker (`/proc/sys/user/max_user_namespaces` reads 160229 inside the container); Docker's default seccomp profile blocks `CLONE_NEWUSER`. Enabling it would require running the bridges with `--privileged`, `--cap-add SYS_ADMIN`, or `seccomp=unconfined`.

That trade is backwards: it punches a hole in the OUTER isolation boundary in order to add an inner one, on containers whose entire purpose is isolating untrusted public input. **For these bridges, the Docker container IS the sandbox.** Do not weaken it to add a nested sandbox. `enableWeakerNestedSandbox` does not rescue this: it addresses a container that cannot mount a fresh `/proc`, not one forbidden from creating namespaces at all.

**The WSL host cannot use it either, for a different reason.** Per the sandbox docs, on WSL2 sandboxed commands cannot launch Windows binaries or anything under `/mnt/c/`. This ecosystem's primary working directory IS `/mnt/c/Users/npeza`, and Windows interop (`wsl.exe`, Chrome/extension paths, Electron apps) is routine. Enabling the sandbox would break that wholesale, and `docker` is separately documented as sandbox-incompatible.

**Where the real mitigation lives instead.** The exposure that motivated this was `Bash(curl:*)` on untrusted public input. Since the OS-level sandbox is unavailable, the controls that DO apply are: the narrow `--allowedTools` list already in `bridge-server.js`, the alt-account isolation, the Docker boundary itself, and the output scrubber. Harden those rather than reaching for `strictAllowlist`.

**Verify before reopening:** run `docker exec -u root <bridge> bwrap --ro-bind / / --dev /dev echo ok`. If it still prints `Operation not permitted`, this conclusion stands.

### Alert on repeat evidence, not the first failure — scale the threshold to whether the fault can self-heal (2026-08-03)

A monitor whose probe path crosses a home network, a WSL vNIC, and an SSH tunnel will fail transiently on a schedule you do not control. Alerting on the first failure treats every transient blip as an outage: a 29-minute WSL network drop that recovered unattended paged Discord on the very first failed check (`consecutive_failures === 1`).

**Scale the threshold to whether the fault can fix itself:**
- **Transport faults** (relay timeout/unreachable, `ERR_NAME_NOT_RESOLVED`, `ERR_NETWORK_CHANGED`, `ECONNREFUSED`, 5xx from the relay) heal on their own. Require ~4 consecutive failures before notifying.
- **Page-level faults** (selector matched nothing, empty capture, HTTP 404 from the target page) will not fix themselves. Notify after ~2 consecutive failures.
- **Recovery notices** should fire only if the error actually alerted. A blip that never crossed the threshold must be silent in both directions — otherwise you have replaced one noisy message with two.

**Two diagnosis traps when a service relays through a home box:**
- The VM logs in UTC; the WSL box logs in local time. A VM error at 10:23 and a WSL error at 03:23 are the same instant during PDT. Run `date -u` on both sides before concluding they disagree.
- A dead reverse tunnel fails in two stages: while `sshd` still holds the forwarded port open, connections are accepted and go nowhere (full client timeout, "relay timeout after 90000ms"); then fail fast once the stale listener is reaped ("relay unreachable: fetch failed"). Both messages in sequence is ONE outage, not two problems.

**PM2 corollary:** a flat `restart_delay` against a genuinely unreachable host produced 48 restarts and several hundred log lines for one outage. Use `exp_backoff_restart_delay` instead. Source: page-watch relay outage, 2026-08-03.

### Rate-limit gates must cover EVERY code path that triggers the limited resource (2026-08-04)

A rate-limit/pacing budget that only guards the scheduled or primary code path is not a budget. Diagnostic commands, probe scripts, and debugging loops run in bursts — they hit the rate-limited resource hardest, at exactly the moments when the scheduled path should be conserved.

Observed in travel-assistant chain-award collection: `pace.json` recorded only `run` calls. `probe` and hand-driven diagnostic loops bypassed the ledger. On two consecutive debug sessions, ~8 hyatt.com loads went through in minutes while the ledger showed 4. hyatt.com returns ZERO-LENGTH bodies after ~6 requests/hour — indistinguishable from "no availability", not an error. The data looked plausible while being wrong.

Rules:
1. **All code paths through a rate-limited resource must go through the same gate.** `run`, `probe`, interactive debugging loops, one-off fix scripts — route them all through `claimRequest()` / the shared gate. If it can hit the API, it must ask for a token first.
2. **`--force` overrides the gate but STILL RECORDS.** An override must not also blind the ledger, or the next caller inherits a false picture of the request count.
3. **Re-read the ledger on each iteration, never cache it.** A probe in another shell is invisible to a run that cached the count at startup.
4. **A budget only one code path respects is not a budget.** Debugging is the path that most needs the gate — it is when one domain gets hit hardest and least evenly.

Applies to any scraper, API client, or browser-automation tool with per-domain/per-hour/per-day request caps.
