# Discord Integration

A private Discord server is the central communication hub for all Claude agents. Every agent session is connected to it: your turns are posted there automatically, the owner issues requests there, and other agents can be reached through it.

**For full Discord details** (server structure, channel IDs, bot commands, specialist agents, per-project channels, inter-agent coordination), see `docs/discord-agent-guide.md` in the `centralDiscord` repo. That file is the single source of truth for Discord-specific documentation.

## What Every Agent Needs to Know

- **Your responses are auto-posted** to `#cli-interactions` via the Stop hook. The hook reads your last response, redacts secrets, and posts it as a Discord embed. You don't need to do anything for this.
- **Threading:** The first turn of a session creates a top-level embed with a thread. All subsequent turns in the same session are posted as thread replies. This keeps conversations grouped and the channel readable.
- **New task = new thread.** When you start working on a distinctly different task within the same session, post a new top-level message to `#cli-interactions` using `discord-webhook.sh` to start a fresh thread. Then delete the session's thread state file (`~/.cache/discord-threads/<session_id>`) so the Stop hook creates a new thread from the next turn. This prevents unrelated work from being buried in the wrong thread.
  ```bash
  ~/repos/privateContext/discord-webhook.sh "Starting new task: <brief description>"
  rm -f ~/.cache/discord-threads/"$CLAUDE_SESSION_ID"
  ```
- **The owner issues requests** in the `#requests` channel. The bot spawns `claude -p` sessions and posts results back.
- **Per-project channels** are auto-created by the bot. Work summaries are crossposted there after each job completes.
- **Specialist agents** (Code Reviewer, DevOps, Architecture, Performance, Testing) can be requested by posting in `#requests` with a tagged description like `[Security Review] ...`.

## Posting to Discord Manually

The webhook URL is stored in `~/.env` as `DISCORD_WEBHOOK_URL`. To post:
```bash
source ~/.env
curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"username":"Claude Agent","content":"Your message here"}'
```

**Limits:** Messages have a **2000-character limit**. Embeds have a 4096-char description limit. When any message exceeds the limit, overflow goes into a thread — `discord-webhook.sh` handles this automatically. For manual posts (raw curl), split into chunks at 1990 chars and post overflow as thread replies.

## Inter-Agent Coordination

- Check `#claude-agent-logs` and `#running-job-logs` to see what other agents are doing before starting work on a shared repo.
- Use per-project channels for handoffs, context dumps, and progress updates.
- Avoid conflicting changes. If another agent is on the same branch, coordinate first.
