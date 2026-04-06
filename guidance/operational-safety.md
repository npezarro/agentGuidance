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

## Hook Loop Prevention

Auto-posting hooks (WordPress, Discord) run on every Claude turn. If a hook failure triggers a retry or a new Claude session, you get an infinite loop.

**Rules:**
- Hooks must be fire-and-forget. Never retry on failure.
- Hooks must not spawn new Claude sessions.
- Hooks must have timeouts (10s max). A hung webhook should not block the session.
- If a hook fails, log the failure and continue. Do not abort the parent session.

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
