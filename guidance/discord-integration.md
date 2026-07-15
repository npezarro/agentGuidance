<!-- Load when: session reporting, posting, threading, file-links -->
# Discord Integration

A private Discord server is the central communication hub for all Claude agents. Every agent session is connected to it: your turns are posted there automatically, the owner issues requests there, and other agents can be reached through it.

**For full Discord details** (server structure, channel IDs, bot commands, specialist agents, per-project channels, inter-agent coordination), see `docs/discord-agent-guide.md` in the `discord-bot` repo. That file is the single source of truth for Discord-specific documentation.

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

## Session Reporting

Every session that produces meaningful work must report to Discord via `~/repos/privateContext/discord-webhook.sh`.

**When to report:**
- After completing a distinct task (feature, fix, deployment, investigation)
- When switching to a different task mid-session
- At session end if any work was done

**How to report** -- use the two-argument form to create a top-level message with a threaded detail:
```bash
~/repos/privateContext/discord-webhook.sh "Project — summary of what changed" "Detailed thread body"
```

Save the returned thread ID. For updates within the same task, reply to the thread:
```bash
~/repos/privateContext/discord-webhook.sh --thread <thread_id> "update text"
```

**Thread discipline:**
- **New task = new top-level message.** When starting a distinctly different task (new project, new feature, switching repos), create a fresh message.
- **Same task updates = thread replies.** Follow-up fixes, deployments of something just built -- reply to the existing thread.

**What to include in the thread detail:**
- What was done, step by step -- enough narrative for someone outside the session to follow
- Why significant choices were made; what was tried that didn't work
- File paths and specific changes; current state (working, not working)
- Follow-ups and open items
- **Reference links** -- include GitHub commit/PR/branch links inline (e.g., "Fixed the validation bug ([commit](https://github.com/npezarro/repo/commit/abc1234))")

**File links (`#file-links`) — AUTOMATED:**
A PostToolUse hook (`auto-file-links.sh`) automatically detects when `git push` includes readable artifacts (.md/.txt files in output/report/proposal/analysis/application directories) and posts them to `#file-links`. You should not need to call `file-links-post.sh` manually in most cases.

**Manual fallback:** If the hook misses a file (e.g., it's in an unusual directory, or you pushed multiple commits), commit and push first (so the GitHub URL resolves), then post manually:
```bash
~/repos/privateContext/file-links-post.sh "Description" "https://github.com/npezarro/repo/blob/branch/path/to/file.md"
```

**What qualifies as a readable artifact:** Reports, analyses, proposals, summaries, application materials — files the user is meant to open and read. Do NOT post links for routine code changes, config files, test files, or internal docs like READMEs.

**All substantive interaction outputs must be pushed to .md files.** This is not limited to "large" outputs. Any CLI interaction that produces a meaningful deliverable (analysis, research, recommendations, comparison, report) must be written to a .md file in the relevant repo, committed, and pushed. Conversation-only output is ephemeral and hard to reference later; files in repos are permanent and searchable.

**Rules:**
- No external posting without explicit instruction. Discord reporting via the webhook script is the one exception -- that's internal.
- Long messages auto-thread. The webhook script splits messages exceeding 2000 chars automatically.
- If the webhook script is not available or fails, continue working -- don't block on reporting.

## Posting to Discord Manually

The webhook URL is stored in `~/.env` as `DISCORD_WEBHOOK_URL`. To post:
```bash
source ~/.env
curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"username":"Claude Agent","content":"Your message here"}'
```

**Limits:** Messages have a **2000-character limit**. Embeds have a 4096-char description limit. When any message exceeds the limit, overflow goes into a thread -- `discord-webhook.sh` handles this automatically. For manual posts (raw curl), split into chunks at 1990 chars and post overflow as thread replies.

## Discord vs CLI Quality Gap

Discord-dispatched agents run with `planMode: 'skip'` and `clarifyAmbiguous: 'best-effort'` — no interactive recovery. When a tool fails (e.g., WebFetch on a JS SPA), the agent can't ask for clarification or retry with user guidance. Mitigations:

- **Server-side URL pre-fetching** in contextFetcher injects page content before the agent starts
- **Belt-and-suspenders**: pre-fetch + EXECUTE_DIRECTIVE fallback instructions + repo CLAUDE.md rules
- **Retry detection**: stripBotOutput() handles users pasting prior bot output with corrections
- When building new Discord-dispatched features, design for single-shot execution — assume no interactive recovery

### VM Skills Availability (Discord vs CLI Mismatch)

Discord-dispatched jobs run `claude -p` **on the VM**, reading `~/.claude/skills` there. Skills added in the local WSL skills repo are NOT automatically available on the VM.

**Symptom:** `#requests` output has degraded formatting or missing sections compared to the same request run locally (e.g., referral blurb absent, cover letter missing sections, no voice-guide compliance). The skill runs locally but not on the VM.

**Fix deployed (2026-06-24):** The Discord bot's `executor.js` `preJobSync()` function now clones/pulls the skills repo on the VM and mirrors every skill dir into `~/.claude/skills` (throttled, once per 5 min).

**Diagnostic:** If Discord output still differs from CLI after the sync fix, SSH to the VM and check:
1. Does the relevant skill exist in `~/.claude/skills/` on the VM?
2. Is the VM's local skills clone up to date? (`git log --oneline -3` in the skills clone dir)
3. Did preJobSync actually run? (Check the most recent `#requests` job log for "skills synced".)

**Why:** A skill added locally silently never reaches Discord-dispatched jobs until the VM sync runs. Discovered when the `write-as-nick` skill was absent on the VM, causing `#requests` resumes to render without formatting or referral blurbs.

## Self-Service Channel & Webhook Creation

Create Discord channels and webhooks yourself using the bot API — don't ask the user to do it. The bot token and guild ID are available in the Discord bot's `.env` on the VM.

**Steps:**
1. Get bot token from the Discord bot's `.env` on the VM
2. `POST /api/v10/guilds/{guild_id}/channels` to create the channel
3. `POST /api/v10/channels/{channel_id}/webhooks` to create the webhook
4. Save webhook URL to VM `~/.env` and local `~/.env`
5. Update `privateContext/accounts.md` with the new channel ID and webhook name

**Why:** The bot token has Manage Channels + Manage Webhooks permissions. Asking the user to create channels manually wastes their time when it's a simple API call.

## App-Level Discord Notifications (Public Apps)

Every public-facing app that runs async jobs (shopper, foodie, travel-assistant, employ) posts job start/complete/fail to its own per-project Discord channel via a `src/lib/discord-notify.ts` module. This is distinct from agent session reporting.

**Pattern** (established across all 4 apps as of 2026-06-18):
- `notifyJobStart(channel, jobId, query)` — posts header message, saves `discord_msg_id` in DB
- `notifyJobComplete(channel, jobId, result)` — edits header in place, posts result as thread reply
- `notifyJobFail(channel, jobId, error)` — edits header in place with error emoji
- Header uses edit-in-place so the channel isn't flooded with redundant messages
- 2000-char limit on Discord messages — truncate gracefully

**When creating a new public app:** copy `discord-notify.ts` from shopper as the base, add `discord_msg_id`/`discord_thread_id` columns to the DB schema, post on every state transition.

**Why:** Silent job failures are invisible without this. The pattern was retro-fitted to all 4 apps; start with it from day 1 on new apps.

## Inter-Agent Coordination

- Check `#claude-agent-logs` and `#running-job-logs` to see what other agents are doing before starting work on a shared repo.
- Use per-project channels for handoffs, context dumps, and progress updates.
- Avoid conflicting changes. If another agent is on the same branch, coordinate first.
