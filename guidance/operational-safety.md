# Operational Safety

Prevent feedback loops, restart storms, and cascading failures in automated systems.

## Self-Deploy Loop Prevention

**The scenario:** A Claude agent job modifies the bot that spawned it, then deploys or restarts that bot. The bot restarts, recovers the "active" job from persistence, re-attaches to the still-running process, and the cycle repeats. Each restart kills in-flight work and creates cascading failures.

**How it happens:**
1. Bot spawns a Claude job targeting the bot's own repo (e.g., centralDiscord)
2. Claude finishes changes and runs `pm2 restart claude-bot` or `vm-ops.sh deploy claude-bot`
3. Bot restarts, loads `jobs.json`, finds the job still "active"
4. Bot re-attaches to the process (or re-queues the job)
5. The job or a recovered job triggers another restart
6. Repeat indefinitely

**Defenses (layered):**

1. **Hard guard in vm-ops.sh:** The `deploy` and `restart` verbs check `data/jobs.json` for active jobs before restarting `claude-bot`. If jobs are active, the command is refused with an error. This is the primary barrier.

2. **Prompt-level warning in executor.js:** When a job's working directory is inside the bot repo, a `selfRestartGuard` message is prepended to the prompt telling Claude not to restart the bot. This is a soft barrier (Claude can ignore it).

3. **SIGINT handler in index.js:** The bot refuses SIGINT during startup (30s grace) and while jobs are active. PM2 sends SIGTERM to force shutdown. This prevents cascading SIGINTs from child processes.

**If a loop is already happening:**
1. Kill the stale child processes: `ps aux | grep claude | grep -v grep` then `kill <pids>`
2. Clear the persisted jobs: edit `data/jobs.json`, set `"activeJobs": []`
3. The bot will stabilize on next restart with no jobs to recover

**Rule:** Never deploy or restart a service from within a job that service spawned. Make changes, commit, push, and note that a manual restart is needed.

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
