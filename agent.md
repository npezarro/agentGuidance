# Global Agent Rules

> **THIS IS A PUBLIC REPOSITORY.** Everything committed here is visible to the entire internet. Never commit secrets, credentials, API keys, tokens, webhook URLs, passwords, private IPs, internal hostnames, `.env` contents, or any other sensitive information — not in code, not in comments, not in examples, not in commit messages. If you need to reference a secret, use a placeholder like `YOUR_API_KEY_HERE` or `[REDACTED]`. When in doubt, leave it out. A leaked secret in a public repo cannot be un-leaked — it must be rotated immediately.

## Identity & Default
- **Primary stack:** JavaScript / Node.js, React (functional components + hooks, Tailwind), HTML/CSS, Google Apps Script, Tampermonkey userscripts.
- **Secondary:** Python (scripting only), Bash, Markdown.
- **Package managers:** npm (preferred); pip when Python is required.
- **Environments:** macOS, Chrome, VS Code, Claude Code CLI, Claude.ai.
- **GitHub:** github.com/npezarro — personal repos, not production services.

## Commands
```bash
npm install          # JS deps
npm run build        # validate before commit — ALWAYS run this
npm run dev          # local dev server (when applicable)
npx jest             # tests (when present)
```

## Planning & Execution
- **Plan before coding.** For anything beyond a single-file fix, outline the approach (files affected, sequence, risks) and confirm before implementing.
- **Ask, don't guess.** If the prompt is ambiguous or missing constraints, stop and ask immediately.
- **Validate incrementally.** Run the build after changes. Never commit broken code.
- **Targeted edits only.** Do not overwrite entire files. Use precise insertions and replacements. Re-read files post-edit to verify surrounding code integrity.
- **Dry-run first.** Use `--dry-run` for destructive or bulk commands when available.
- **Diagnose before retrying.** If a command fails, understand *why* before re-running. No blind retry loops.

## Batching & Checkpointing
Large tasks (processing many files, writing long documents, multi-step deployments) are the #1 cause of crashes and lost work.
- **Break output into batches of 5–10 items.** Never try to write 50+ things at once.
- **Commit and push after each batch.** If the session crashes, completed work is preserved.
- **For file sets over ~100 files:** Write a Python/Bash script to process them instead of reading each one directly.
- **When deleting files:** Only delete files in the explicitly approved categories. Do not expand scope, infer "duplicates," or add categories without asking. List what will be deleted and confirm before executing.

## Git Workflow
- Never commit directly to `main`.
- Use the branch assigned to you. If none exists, create one: `agent/<task-name>` or `claude/<task-name>`.
- Commit messages explain **why**, not just what. Large commits are fine — don't split work artificially.
- Before committing:
  1. `git status` — verify no unintended files staged.
  2. `git diff` — review the actual changes.
  3. Confirm no `.env`, secrets, or key files are included.
  4. **Update `context.md`** — this is mandatory for any commit that changes code or configuration. See the Context File section below.
- Push: `git push -u origin HEAD`. Retry network failures up to 4× with backoff (2s, 4s, 8s, 16s). Do not retry auth failures.
- **Creating PRs:**
  ```
  gh pr create --title "<task>" --body "<context>"
  ```
- **Before creating a PR, check for existing PRs** to avoid duplicate/colliding PR numbers:
  ```
  gh pr list --state all --head <branch-name>
  ```
  If a PR already exists for the branch, update it instead of creating a new one.
- If `gh` is not available or not authenticated, provide the manual PR URL:
  ```
  https://github.com/<owner>/<repo>/pull/new/<branch-name>
  ```
- Do **not** enable auto-merge unless explicitly asked.

## Context File (`context.md`)
**This is not optional.** Every repo must have a `context.md` at its root. It is the handoff document between sessions — the way the next agent (or the next you) picks up where the last one left off. Treat it like a relay baton: if you don't pass it, the next runner starts blind.

### When to update
- **Every commit that changes code or configuration.** Include the `context.md` update in the same commit — not as a separate follow-up.
- **When you discover something about the environment** — a port, a config path, a quirk that's not documented yet.
- **At the end of a session**, even if you didn't push. If you investigated something, made a decision, or identified a blocker, capture it.

### What to write
Keep it concise and current. This is a living status page, not a changelog.

```
# context.md
Last Updated: YYYY-MM-DD — one-line summary
Current State: what works, what's deployed, known issues
Recent Changes: what changed and why (keep brief, most recent first)
Open Work: blockers, unfinished tasks, decisions needed
Environment Notes: deploy target, process manager, ports, SSH user, config file paths
Active Branch: current working branch name
```

### What NOT to include
- Credentials, API keys, tokens, passwords, or `.env` contents — ever.
- Verbose history — this isn't a git log. Keep "Recent Changes" to the last 3–5 entries. Older items can be removed.

### Environment Notes must include (when applicable)
- SSH user and hostname
- PM2 process name and port
- Web server config file path (e.g., Apache VirtualHost location)
- Base path if deployed to a subdirectory
- Database file path
- Node version, if it matters for the project

### If `context.md` doesn't exist yet
Create it from the template at `agentGuidance/templates/context.md`. Fill in what you can from the repo's config files, `package.json`, and environment. Don't leave placeholder comments — either fill in the value or remove the line.

## Testing
- **Run existing tests before making changes.** Know the baseline — don't introduce regressions.
- **Run tests after changes.** `npx jest`, `npm test`, or whatever the repo uses. Check `package.json` for the test command.
- **Write tests when:**
  - Fixing a bug (regression test proving the fix).
  - Adding a function with non-trivial logic (edge cases, error paths).
  - The repo already has a test suite (match its patterns).
- **Don't write tests when:**
  - The repo has no test infrastructure and you weren't asked to add one.
  - The change is purely cosmetic (copy, styling, config).
- **Test structure:** Arrange-Act-Assert. One assertion per behavior. Descriptive test names that read as sentences.
- **Mocks:** Only mock external boundaries (network, file system, databases). Never mock the unit under test.

### Regression & Functional Verification
Unit tests alone are not enough. **After every change, verify that existing user flows still work.** Regressions — features that were working but break silently during development — are the most damaging bugs because they ship unnoticed.

- **Identify critical user flows before coding.** Before making changes, list the key paths a user takes through the app (e.g., sign in → dashboard → connect integrations → view data). These are your regression checklist.
- **Test every flow after changes, not just the one you touched.** A change to auth middleware can break the dashboard. A change to a shared component can break pages that import it. Assume your change has side effects until proven otherwise.
- **For web apps:** After building, manually verify (or script verification of) these at minimum:
  - Authentication works (sign up, sign in, sign out)
  - Authenticated pages are accessible after sign-in (dashboard, settings, profile)
  - Core integrations and connected services still function (OAuth flows, API callbacks, webhooks)
  - Navigation between pages works without errors
  - API endpoints return expected responses (use `curl` or the app itself)
- **Check server logs after testing.** `pm2 logs`, browser console, or network tab — look for errors, 500s, redirects to wrong pages, and failed API calls that the UI might silently swallow.
- **If the app has multiple user states, test each one.** Logged out vs. logged in. New user vs. returning user. User with connected services vs. without. Admin vs. regular user.
- **Don't assume "it builds, so it works."** A clean build means the code compiles — it does not mean the app behaves correctly. Build success is necessary but not sufficient.
- **When a regression is found:** Fix it before moving on to new work. Document what broke and why in the commit message — this prevents the same class of bug from recurring.
- **Before declaring a task complete:** Run through the full regression checklist one final time. If you cannot verify a flow (e.g., OAuth requires real credentials), flag it explicitly in `context.md` as untested.

## Debugging
- **Reproduce first.** Before changing code, confirm you can trigger the issue.
- **Read the error.** Stack traces, error codes, and log output contain the answer more often than not. Read them fully.
- **Isolate the problem.** Binary-search through the code path. Add targeted `console.log` or breakpoint, not scattered print statements.
- **Check the obvious:**
  - Is the right branch deployed / running?
  - Are environment variables loaded?
  - Is the correct version of the dependency installed?
  - Is there a typo in a variable name, route, or selector?
- **Use git history.** `git log --oneline -20`, `git diff HEAD~1`, `git bisect` — find what changed.
- **Don't fix symptoms.** If a variable is unexpectedly `undefined`, trace *why* instead of adding a null check.
- **Document the fix.** Commit message should explain the root cause, not just "fix bug."

## Dependency Management
- **Minimize new dependencies.** Before adding a package, check if the standard library or existing deps already solve the problem.
- **Evaluate before installing:**
  - Is it actively maintained? (check last publish date, open issues)
  - How large is it? (`npm info <pkg> | grep size` or check bundlephobia)
  - Does it have known vulnerabilities? (`npm audit`)
  - Is the license compatible? (MIT, Apache-2.0, ISC are safe)
- **Pin versions.** Use exact versions in `package.json` for deployed apps. Use `--save-exact` or lockfiles.
- **Don't mix package managers.** If the repo uses `npm`, don't run `yarn` or `pnpm`.
- **After installing:** Run the build and tests. New deps can introduce conflicts.
- **Keep lockfiles committed.** `package-lock.json` or `yarn.lock` must be in version control.

## Code Standards
- **Match existing patterns.** Read `package.json`, config files, and surrounding code before writing anything. Do not introduce new frameworks, ORMs, or styling approaches without explicit approval.
- **JS/TS style:** Functional, ES modules, modern syntax (async/await, optional chaining, destructuring). React: functional components, hooks, Tailwind — no class components.
- **Logging:** Use `console.log` / `console.error` liberally in scripts and prototypes. For deployed or user-facing code, log errors and key state transitions only.
- **No over-engineering.** Solve the stated problem. Don't add abstraction layers, feature flags, or refactors beyond what was asked.
- **Error handling:** Handle errors at system boundaries (user input, API calls, file I/O). Use early returns for validation. Let internal errors propagate — don't swallow them with empty `catch` blocks.

## Environment Awareness
Before starting work on a deployed project:
- **Check what's already running:** `pm2 list`, `ss -tlnp | grep <port>`, `ps aux | grep <process>`.
- **Check file ownership:** If `npm install` fails with EACCES, run `sudo chown -R $(whoami):$(whoami) <project-dir>` before retrying.
- **Check if you're already on the target server** before SSH-ing anywhere.
- **After changing `.env` values:** Rebuild (`npm run build`), not just restart. Static pages bake env vars at build time.
- **Store environment metadata** (SSH user, hostname, PM2 name, port) in `context.md`, not in committed code or `.env`.

## Documentation Freshness
- Assume internal knowledge of APIs, SDKs, and libraries may be outdated.
- Search for current docs before implementing anything version-sensitive (model APIs, SDK methods, breaking changes).

## Security
**This repo (`agentGuidance`) is public.** It is indexed by search engines and visible to anyone on the internet. Every other repo you work on may be private, but this one is not. Treat every commit, every file, every line as if it will be read by strangers — because it will be.

- **No secrets in commits, PRs, context files, or logs. Ever.** This includes API keys, tokens, passwords, webhook URLs, Discord bot tokens, database credentials, private IPs, internal hostnames, and `.env` contents.
- **Environment-specific values belong in `.env` or local config**, never in committed code. Use placeholders like `YOUR_API_KEY_HERE` or `$ENV_VAR_NAME` in examples.
- **Audit before every commit to this repo.** Run `git diff --staged` and read every line. Ask yourself: "Would I be comfortable if a stranger read this?" If not, redact or remove it.
- **Do not reference real infrastructure details** (server IPs, SSH usernames, ports, PM2 process names, domain-specific paths) in this repo. Those belong in each project's private `context.md` or `.env`, not in shared public guidance.
- **If a secret is accidentally committed**, treat it as compromised. Rotate the credential immediately, then remove it from git history with `git filter-branch` or `bfg`. A force-push to clean history is justified in this case — and only this case.

## Discord Integration
A private Discord server is the central communication hub for all Claude agents. Every agent session is connected to it — your turns are posted there automatically, the owner issues requests there, and other agents can be reached through it. **Discord is not optional.** Every agent is expected to use it as the coordination layer between sessions, between agents, and between agents and the owner.

### Server Structure
- **Guild ID:** `REDACTED_GUILD_ID`
- **`#claude-agent-logs`** (ID: `REDACTED_CHANNEL_ID`) — Every Claude Code turn is auto-posted here as a webhook embed via the Stop hook. The owner can reply to any embed to trigger a follow-up Claude invocation with context from the original turn. This is the global activity feed — all agents post here automatically.
- **`#requests`** — The owner posts jobs here. The bot (ClaudeAgent) picks them up, runs `claude -p --dangerously-skip-permissions`, and posts results back as replies. A completion notice with a link to the original request is also posted in `#claude-agent-logs`. **You can also post requests here** to ask for specialist agents, channel creation, or coordination with other agents.
- **`#running-job-logs`** — Live progress feed for in-flight Claude jobs. When a `claude -p` invocation starts (from `#requests` or a reply in `#claude-agent-logs`), the bot posts a status message here and **edits it every 2 minutes** with elapsed time and output size. When the job finishes or fails, the message is updated with the final status. Use this channel to monitor long-running jobs without waiting in `#requests`.
- **Per-project channels** (e.g., `#runeval`, `#central-discord`, `#agent-guidance`) — **Auto-created** by the bot when a project is first referenced in a request or reply. Work summaries are automatically crossposted here after each job completes. Use these channels for focused discussion, progress updates, context dumps, and inter-agent coordination. See "Per-Project Channels" below.

### How Auto-Posting Works
Every Claude Code response is automatically posted to `#claude-agent-logs` via the Stop hook — you don't need to do anything for this. The hook:
1. Reads the last assistant message from the session transcript
2. Redacts secrets (tokens, API keys, passwords, private IPs)
3. Posts as a Discord embed with the project name, session ID, and the user's prompt as context
4. Overflow content (responses > 3900 chars) is split into follow-up code blocks (up to 3 chunks)

This means your responses are always visible to the owner and other agents in the server. Write accordingly.

### Posting to Discord Manually
Beyond auto-posting, you can post messages to Discord programmatically when you need to communicate something outside the normal turn flow — progress updates, alerts, requests for help, or coordination messages.

The webhook URL is stored in `~/.env` as `DISCORD_WEBHOOK_URL`. To post:
```bash
# Load the webhook URL
source ~/.env

# Simple message
curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"username":"Claude Agent","content":"Your message here"}'

# Message with embed (for structured data)
curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "Claude Agent",
    "embeds": [{
      "title": "Build Failed — runeval",
      "description": "npm run build exited with code 1. See #runeval for details.",
      "color": 15548997
    }]
  }'
```

**Limits:** Messages have a **2000-character limit**. Embeds have a 4096-char description limit. Split longer content into chunks.

**From Node.js:** Use the helpers in `discord-bot/src/webhooks/send.js`:
```javascript
const { sendWebhook, sendWebhookEmbed } = require('./src/webhooks/send');
await sendWebhook('Build complete', { username: 'Claude Agent' });
await sendWebhookEmbed('Deploy Status', 'runeval deployed successfully', { color: 0x57F287 });
```

### Per-Project Channels
Per-project channels are **auto-created by the bot** the first time a project is referenced in a request or reply. You do not need to create them manually — the bot handles it. When a job completes, the bot automatically crossposts a work summary to the project's channel.

**Auto-creation rules:**
- The bot converts project names to kebab-case channel names: `discord-bot` → `#central-discord`, `agentGuidance` → `#agent-guidance`, `runeval` → `#runeval`
- Channels are created as standard text channels with a topic like "Project channel for X — auto-created by ClaudeAgent"
- If the channel already exists, the bot reuses it

**What gets crossposted automatically:**
- When a `#requests` job completes, the full result is posted in the project channel with a link back to the original request
- When a reply-based job completes in `#claude-agent-logs`, the result is crossposted to the project channel
- Both successes and the final output are captured — you don't need to do anything

**What you should post manually in project channels:**
- **Context dumps** — When starting a multi-session task, dump relevant context (current state, recent git log, open issues) into the project channel so the next agent can pick it up without reading `context.md`
- **Build/test results** — After running builds or tests, post the results
- **Debugging findings** — Root cause analysis, stack traces, and the fix
- **Decision records** — "Chose X over Y because..." — these are invaluable for future sessions
- **Blockers and requests for help** — Flag what's stuck and what you need
- **Deploy status** — Before/after deploy summaries
- **Links to relevant PRs, commits, or issues**

**How to post to a project channel manually:**
```bash
# Load webhook URL
source ~/.env

# Post to the project channel via webhook
curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"username":"Claude Agent","content":"[runeval] Build passed. Deploying to production."}'
```

Or from the bot's actions library:
```javascript
const { sendMessage } = require('./actions');
await sendMessage(client, channelId, 'Build passed. Deploying to production.');
```

**Naming conventions:**
- Lowercase, hyphenated, derived from the project directory name
- Examples: `#runeval`, `#central-discord`, `#pezant-tools`, `#agent-guidance`

### Running Job Logs (`#running-job-logs`)
The `#running-job-logs` channel provides **real-time visibility** into in-flight Claude jobs. You don't need to do anything — the bot manages this automatically.

**What happens when a job starts:**
1. The bot posts a status message with: source (request or reply), project name, requester, instruction snippet, and working directory
2. Every **2 minutes**, the bot edits this message with updated elapsed time and output size
3. When the job completes, the message is updated to show final duration and output size
4. If the job fails, the message is updated with the error

**Why this matters:**
- Long-running jobs (builds, deploys, large refactors) can take 5-20+ minutes
- Without progress visibility, you don't know if a job is stuck, still working, or about to finish
- The 2-minute heartbeat confirms the job is alive and making progress
- The owner can monitor all active work from a single channel

### Receiving and Responding to Requests
The `#requests` channel is a two-way street. The owner posts jobs there, but **you can also use it to:**
- Request a specialist agent (see below)
- Ask for a channel to be created
- Flag a blocker that needs human intervention
- Coordinate with another agent working on a related task

**How requests work:**
1. A message is posted in `#requests`
2. The bot reacts with a hourglass emoji to acknowledge
3. The bot spawns a `claude -p` session with the request text as the prompt
4. The working directory is resolved from the project context in the message
5. The result is posted back as a reply in `#requests`
6. A completion notice is posted in `#claude-agent-logs`

Only the server owner and authorized users (configured via `CLAUDE_ALLOWED_USERS`) can trigger requests. One request runs at a time — the bot queues if already processing.

### Specialist Agents
When you encounter a problem outside your expertise — security review, performance profiling, database optimization, architecture decisions — you can request a specialist agent. These are independent `claude -p` sessions with tailored system prompts that bring focused expertise to a specific problem.

**How to request a specialist:**
Post in `#requests` with a clear description of what you need and why:
```
[Security Review] Review the auth middleware in npezarro/runEvaluator for session
fixation, CSRF, and token leakage vulnerabilities. Focus on src/middleware/auth.js
and src/pages/api/auth/*.js.
```

**Available specialist roles:**
- **Code Reviewer** — Security audits, code quality review, PR review. "Review PR #5 on npezarro/runEvaluator for XSS and injection vulnerabilities"
- **DevOps Specialist** — Infrastructure debugging, PM2 issues, deploy failures, server config. "Debug why PM2 keeps restarting the runeval process every 30 seconds"
- **Architecture Advisor** — Design decisions, migration planning, tech stack evaluation. "Evaluate whether we should migrate runeval from Pages Router to App Router — what breaks, what improves?"
- **Performance Analyst** — Profiling, optimization, database query analysis. "The dashboard API endpoint takes 4 seconds — profile the query chain and suggest optimizations"
- **Test Engineer** — Test strategy, coverage analysis, test infrastructure setup. "Design a test suite for the OAuth integration in runeval — what should we test and how?"

**How specialist output is delivered:**
- The specialist runs as a `claude -p` invocation with the request as context
- Output is posted back as a reply in the channel where the request was made
- A completion notice appears in `#claude-agent-logs`
- If a project channel exists, the specialist's findings can be cross-posted there

**When to use a specialist vs. solving it yourself:**
- Use a specialist when you've hit a wall or the problem is outside your current task's scope
- Use a specialist when a second opinion would prevent a costly mistake (security, architecture)
- Don't use a specialist for routine tasks you can handle — they're for focused expertise, not delegation

### Inter-Agent Coordination
Multiple agents may be working on related projects simultaneously. Discord is how you coordinate:

- **Check `#claude-agent-logs` context.** Your auto-posted turns are visible to other agents. If another agent is working on the same repo, you'll see their activity in the feed.
- **Check `#running-job-logs` before starting work.** If another job is already running on the same project, wait for it to finish or coordinate to avoid conflicts.
- **Use project channels for handoffs.** If you're done with a subtask and another agent needs to pick it up, post the status in the project channel with clear next steps. The bot already crossposts job results there — add any context the result doesn't capture.
- **Dump context in project channels.** At the start of a multi-session task, post the current state (recent git log, open issues, environment notes) in the project channel. This supplements `context.md` with Discord-accessible context that other agents can find without cloning the repo.
- **Avoid conflicting changes.** If you see another agent is actively working on the same branch or file, coordinate via `#requests` or the project channel before making changes.
- **Share discoveries.** If you find a bug, a gotcha, or a useful pattern while working, post it in the relevant project channel so other agents (and future sessions) benefit.

### The Bot (`YourBot#0000`)
**PM2 process:** `your-bot-process` | **Code:** `$HOME/discord-bot`

**Capabilities:**
- Read and send messages in any visible channel
- Create and manage channels and threads
- Create and manage roles (no admin or invite perms)
- Pin messages, set channel topics, add reactions
- Manage webhooks
- Spawn `claude -p` sessions on behalf of authorized users
- Route requests to the correct project working directory

**Built-in commands:**
- `!ping` — Check if the bot is alive
- `!status` — Show guild stats (members, channels, uptime)
- Reply to any webhook embed — Triggers a follow-up Claude session with context from the original turn

**Limitations (by design):**
- Cannot create server invites
- Cannot make the server discoverable
- Cannot grant administrator permissions
- One `claude -p` invocation at a time (queued, not parallel)

## Auto-Posting Awareness
Every Claude Code response is automatically posted to **two destinations** via Stop hooks:
1. **WordPress** — as a private draft on YOUR_DOMAIN (the blog post).
2. **Discord** — as an embed in the `#claude-agent-logs` channel on the private Discord server.

Your response IS the blog post and the Discord log entry. Write accordingly — both audiences are human readers.

### Security
- **Never include raw secret values** — API keys, tokens, passwords, application passwords, database credentials, SMTP passwords, or `.env` file contents.
- **Redact when referencing secrets.** Show `VARIABLE_NAME=[REDACTED]` or describe it without revealing the value.
- **Avoid echoing sensitive command output.** Summarize the result without printing the raw value.
- **Private repo names are fine** — this applies to secret *values*, not repo names.
- **Never include Discord tokens, webhook URLs, or bot tokens** — these are secrets, same as API keys.
- The hook scripts (WordPress and Discord) both perform pattern-based redaction as a safety net, but do not rely on them — treat every response as potentially public.

### Writing Style
Write every response as a **first-person blog post** — as if you are the developer narrating what you did and why. This is critical. Your response will be read by humans on a blog, not parsed by machines in a terminal.

**Voice and tone:**
- First person, active voice: "I updated the hook script to..." not "The hook script was updated to..."
- Write in full sentences and paragraphs, not terse bullet-point summaries
- Explain *why* something was done, not just *what* — "The posts were rendering raw markdown because the hook had no conversion step, so I added a function that..."
- Use headings (##, ###) to break up sections when covering multiple topics
- Keep the tone conversational and direct — like a developer writing a devlog, not a changelog

**Structure each response as a self-contained episode:**
- **Start with a descriptive heading.** Your first `##` heading becomes the WordPress post title. Make it specific and meaningful — it should tell a reader what this post is about without clicking through. Good: `## Propagating Claude Code Hooks to All 30 Repos`. Bad: `## What I Changed`, `## Summary`, `## The Fix`. Think of it like an article headline, not a section label.
- **Open with context.** One or two sentences orienting the reader: what project, what problem, what's the goal. Like a "previously on..." cold open — just enough for someone who missed the last episode to follow along.
- **Tell the story.** Walk through what you investigated, decided, and built. Include the reasoning. Show code snippets or config excerpts when they clarify the narrative — but don't dump raw terminal output.
- **Close with state.** End with what's done, what works, and what comes next — so the next episode has a clean starting point.

**What NOT to do:**
- Don't write terse summaries like "Done. Three fixes applied:" followed by a bullet list. That's a commit log, not a blog post.
- Don't echo the user's prompt back at them. They know what they asked.
- Don't list tool calls or file operations mechanically. Weave them into the narrative.
- Don't use `**bold**` for every other word. Reserve emphasis for key terms and important callouts.

## Code Review (Self-Review Before Committing)
Before every commit, run through this checklist:
1. **Diff review:** `git diff --staged` — read every line. Does each change serve the stated goal?
2. **No debug artifacts:** Remove `console.log`, `debugger`, `TODO: remove`, commented-out code added during development.
3. **No secrets:** Grep for API keys, tokens, passwords, hardcoded URLs with credentials.
4. **Build passes:** `npm run build` (or equivalent) exits cleanly.
5. **Tests pass:** `npm test` (or equivalent) — no regressions.
6. **File hygiene:** No unintended files staged (`.DS_Store`, `node_modules/`, build artifacts).
7. **Naming:** Variables, functions, and files follow existing conventions in the codebase.
8. **Edge cases:** Did you handle empty inputs, missing data, and error states?

## Communication
- **Be concise.** Lead with the answer or action, then provide supporting detail.
- **Show, don't tell.** Include relevant code snippets, commands, or file paths — not vague descriptions.
- **Progress updates:** For multi-step tasks, report what was completed after each step, not just at the end.
- **Flag blockers immediately.** Don't silently struggle. If something is unclear, missing, or broken, say so.
- **Summarize at the end.** After completing a task, provide a brief summary: what changed, what was tested, what to watch for.
- **Use structured output** for lists, comparisons, and multi-part answers. Bullet points and tables are easier to scan than paragraphs.

## Multi-Session Continuity
When picking up work from a previous session (yours or another agent's):
1. **Read `context.md` first.** It's the handoff document.
2. **Check git log.** `git log --oneline -10` — understand recent changes.
3. **Check git status.** Look for uncommitted work left behind.
4. **Check for open PRs.** `gh pr list` — don't duplicate existing work.
5. **Verify the environment.** Are dependencies installed? Is the build working? Are services running?
6. **Update `context.md` when you're done.** The next session depends on it.

## Session Wrap-Up
**Before ending any session where you wrote or changed code, you MUST complete all of these steps.** Do not wait to be asked — this is automatic.

1. **Update `context.md`** — reflect the current state of the project, what changed, and any open work.
2. **Commit all changes.** Stage relevant files (never `.env`, secrets, or build artifacts). Write a commit message that explains *why*, not just *what*.
3. **Push to remote.** `git push -u origin HEAD`. Confirm the push succeeded.
4. **Verify nothing was left behind.** Run `git status` after pushing — there should be no uncommitted changes related to the task.

If the build is broken and you cannot fix it before the session ends, still commit and push with a clear note in the commit message and `context.md` explaining the broken state so the next session can pick it up. Uncommitted local changes are invisible to future sessions and effectively lost work.

## Deployment
- Infer deploy commands from repo config (GitHub Actions, scripts, `context.md`).
- **Pre-deploy checklist:**
  1. All changes committed and pushed via PR.
  2. Build succeeds locally.
  3. Tests pass.
  4. `context.md` updated with deployment intent.
  5. No secrets exposed in repository history.
  6. Dependencies are locked (`package-lock.json` committed).
- **Post-deploy:**
  1. Verify the deployment is live and functioning.
  2. Update `context.md` with deployment status.
  3. Monitor for errors in the first few minutes if logs are accessible.
