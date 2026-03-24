<!-- agent.md v2.0.0 | Last updated: 2026-03-22 -->
# Global Agent Rules

> **THIS IS A PUBLIC REPOSITORY.** Everything committed here is visible to the entire internet. Never commit secrets, credentials, API keys, tokens, webhook URLs, passwords, private IPs, internal hostnames, `.env` contents, or any other sensitive information. Use placeholders like `YOUR_API_KEY_HERE` or `[REDACTED]`.

## Session Startup Confirmation

**At the start of every session, before doing any work, output the following confirmation:**

> **Agent ready.** Read agent.md, context.md, and progress.md. Stack: [primary stack from context]. Branch: [current branch]. Open work: [count] items. Private context: [available/not found].

If any file is missing or unreadable, say so explicitly. Do not skip this step.

## Identity & Defaults
- **Primary stack:** JavaScript / Node.js, React (functional components + hooks, Tailwind), HTML/CSS, Google Apps Script, Tampermonkey userscripts.
- **Secondary:** Python (scripting only), Bash, Markdown.
- **Package managers:** npm (preferred); pip when Python is required.
- **Environments:** macOS, Chrome, VS Code, Claude Code CLI, Claude.ai.
- **GitHub:** github.com/npezarro (personal repos, not production services).

## Commands
```bash
npm install          # JS deps
npm run build        # validate before commit. ALWAYS run this
npm run dev          # local dev server (when applicable)
npx jest             # tests (when present)
```

## Capture Every Learning
**This is a top priority.** When a session produces a learning, correction, process change, or new convention, it must be captured in version-controlled guidance before the session ends. Learnings that stay only in conversation context are lost.
- **Cross-project learnings** (process, conventions, tooling): update `agentGuidance` (agent.md for core rules, or the appropriate `guidance/*.md` file for detailed procedures).
- **Project-specific learnings** (architecture decisions, gotchas, environment quirks): update that project's `CLAUDE.md`, `context.md`, or a relevant doc in the repo.
- **If the owner corrects your approach or gives feedback that should apply going forward**, codify it immediately. Don't just acknowledge it for this session.
- When in doubt about where a learning belongs, prefer `agentGuidance` (it's read by all sessions) over project-local files.

## Planning & Execution
- **Plan before coding.** For anything beyond a single-file fix, outline the approach (files affected, sequence, risks) and confirm before implementing.
- **Ask, don't guess.** If the prompt is ambiguous or missing constraints, stop and ask immediately.
- **Validate incrementally.** Run the build after changes. Never commit broken code.
- **Targeted edits only.** Do not overwrite entire files. Use precise insertions and replacements. Re-read files post-edit to verify surrounding code integrity.
- **Dry-run first.** Use `--dry-run` for destructive or bulk commands when available.
- **Diagnose before retrying.** If a command fails, understand *why* before re-running. No blind retry loops.
- **Always push to GitHub.** When working on code or producing written materials, commit and push to the relevant repo. The remote is the source of truth.
- **Track prep in the pipeline.** When producing application materials for a role: (1) create a prep file in `llm-tasks/applications/` with experience mapping, STAR stories, interview questions, cover letter, referral blurb, and outreach draft; (2) create a company folder (e.g., `applications/adobe/`) with tailored resume and cover letter as both markdown and PDF, named `Resume - Company, Role Title` and `Cover Letter - Company, Role Title`; (3) include resume tweak notes explaining what was changed and why for each role; (4) push to GitHub; (5) append the role to the Job Data tab in the Google Sheet (see `privateContext/infrastructure.md`) with a link in the "Application Materials" column. Use the latest dated resume in `resumes/` as the baseline. Convert to PDF via `pandoc file.md -o file.pdf --pdf-engine=pdflatex -V geometry:margin=0.75in -V fontsize=10pt -V linkcolor=blue`.
- **No external posting without explicit instruction.** Never post, submit, register, or publish to external sites or APIs unless the user explicitly asks. Building features that *could* post is fine; actually calling endpoints is not.

## Batching & Checkpointing
Large tasks (processing many files, writing long documents, multi-step deployments) are the #1 cause of crashes and lost work.
- **Break output into batches of 5-10 items.** Never try to write 50+ things at once.
- **Commit and push after each batch.** If the session crashes, completed work is preserved.
- **For file sets over ~100 files:** Write a Python/Bash script to process them.
- **When deleting files:** Only delete files in explicitly approved categories. List what will be deleted and confirm before executing.

## Git Workflow
Never commit directly to `main`. Use assigned branch or create `agent/<task-name>`. Commit messages explain *why*. Push with `git push -u origin HEAD`. See `guidance/git-workflow.md` for PR creation, branch hygiene, and merge procedures.

## Context File & Progress Log
Every repo must have `context.md` (current state snapshot) and `progress.md` (append-only changelog). Update `context.md` on final branch commits and session end. Update `progress.md` on every commit. See `guidance/context-progress.md` for full specs and templates.

## Testing
Run existing tests before and after changes. Write tests for bug fixes and non-trivial logic. See `guidance/testing.md` for regression verification procedures and testing standards.

## Debugging
Check logs first (`pm2 logs`, DevTools console). Reproduce, isolate, then fix. See `guidance/debugging.md` for full procedures.

## Dependencies
Minimize new dependencies. Evaluate maintenance, size, vulnerabilities, and license before installing. See `guidance/dependencies.md` for details.

## Code Standards
- **Match existing patterns.** Read `package.json`, config files, and surrounding code before writing anything.
- **JS/TS style:** Functional, ES modules, modern syntax. React: functional components, hooks, Tailwind.
- **No over-engineering.** Solve the stated problem. Don't add abstraction layers beyond what was asked.
- **Error handling:** Handle errors at system boundaries. Let internal errors propagate.

## Environment Awareness

See `guidance/resource-awareness.md` and `guidance/process-hygiene.md` for detailed procedures. See `guidance/operational-safety.md` for preventing self-deploy loops and restart storms.

Before starting work on a deployed project:
- **Check what's already running:** `pm2 list`, `ss -tlnp | grep <port>`, `ps aux | grep <process>`.
- **Check file ownership:** If `npm install` fails with EACCES, run `sudo chown -R $(whoami):$(whoami) <project-dir>`.
- **After changing `.env` values:** Rebuild (`npm run build`), not just restart. Static pages bake env vars at build time.
- **In WSL, `localhost` is WSL's network stack, not Windows.** Resolve host IP from `/etc/resolv.conf` dynamically.
- **After creating/editing scripts in Windows/WSL:** Check for CRLF line endings (`file <script>`) and fix with `sed -i 's/\r$//'`.

### discord-bot-Specific Rules
- **Re-export chain:** `debate.js` imports from `claudeReply.js`, not `executor.js` directly. New executor exports must be added to claudeReply.js re-exports too.
- **Command registration is two-step:** Add the handler to `commands.js` AND add the command name to the `isBuiltinCommand` regex in `index.js`.
- **Strip mention prefixes:** `message.content` may start with `<@ID>` when users @ the bot. Always strip before regex matching.
- **For detailed post-mortem:** See `guidance/local-worker-bridge.md`.

## Claude Arena (A/B Testing)

**claude-bakeoff** is available for empirical comparison of approaches. When two strategies could be compared rather than debated, use it.

- **Repo:** `~/repos/claude-bakeoff`
- **Run a test:** `arena run <task> --env-a <env1> --env-b <env2>`
- **Evaluate:** `arena eval <run-id>` (auto-posts results to `#claude-bakeoff`)
- **Full docs:** See `guidance/ab-testing.md`

**Opting out:** If the owner says `--no-arena`, do not suggest or use claude-bakeoff for the remainder of the session.

## Cowork Reporting

Claude Cowork sessions are tracked in `~/repos/cowork-sessions` (private repo). Cowork produces structured session log artifacts; local scripts sync them to Discord `#cowork` and GitHub.

- **Session logs:** `cowork-sessions/sessions/YYYY-MM-DD/{slug}.md`
- **Instructions for Cowork:** `cowork-sessions/cowork-instructions-global.md` (paste into claude.ai global custom instructions)
- **Sync to Discord + GitHub:** `cowork-sessions/scripts/sync-latest.sh`

## Cowork Reporting

Claude Cowork sessions are tracked in `~/repos/cowork-sessions` (private repo). Cowork produces structured session log artifacts; local scripts sync them to Discord `#cowork` and the GitHub repo.

- **Session logs:** `cowork-sessions/sessions/YYYY-MM-DD/{slug}.md`
- **Instructions for Cowork:** `cowork-sessions/cowork-instructions.md` (paste into claude.ai project settings)
- **Sync to Discord + GitHub:** `cowork-sessions/scripts/sync-latest.sh`
- **TaskCompleted hook** in `~/.claude/settings.json` posts CLI task completions to `#cowork` automatically

## Private Context Repository

A private companion repo exists at `~/repos/privateContext` with sensitive information that should not be in this public repo. **Consult it when you need:**
- Service account details, OAuth app configurations, API key locations
- Infrastructure specifics (ports, paths, database locations, env var lists)
- Pending manual actions that require human intervention
- Completed work log for deduplication

Do not duplicate information from privateContext into this repo or any other public repo.

## Documentation Freshness
- Assume internal knowledge of APIs, SDKs, and libraries may be outdated.
- Search for current docs before implementing anything version-sensitive.

## Security
- **No secrets in commits, PRs, context files, or logs. Ever.**
- **Environment-specific values belong in `.env` or local config**, never in committed code.
- **Audit before every commit to this repo.** Run `git diff --staged` and read every line.
- **Do not reference real infrastructure details** in this repo. Those belong in private `context.md` or `.env`.
- **If a secret is accidentally committed**, rotate the credential immediately, then remove from git history.

## Discord Integration
Your responses are auto-posted to `#cli-interactions` via the Stop hook. The owner issues requests in `#requests`. See `guidance/discord-integration.md` for threading, manual posting, and inter-agent coordination.

## Auto-Posting Awareness
Every response is auto-posted to WordPress (private draft) and Discord (embed). Write accordingly: front-load meaning, first paragraph must stand alone, target ~3,500 chars for primary content. See `guidance/auto-posting.md` for writing style, multi-destination design, and security rules.

## Code Review (Self-Review Before Committing)
1. **Diff review:** `git diff --staged` and read every line.
2. **No debug artifacts:** Remove `console.log`, `debugger`, `TODO: remove`, commented-out code.
3. **No secrets:** Grep for API keys, tokens, passwords, hardcoded URLs with credentials.
4. **Build passes:** `npm run build` exits cleanly.
5. **Tests pass:** `npm test`. No regressions.
6. **File hygiene:** No unintended files staged (`.DS_Store`, `node_modules/`, build artifacts).
7. **Naming:** Variables, functions, and files follow existing conventions.
8. **Edge cases:** Did you handle empty inputs, missing data, and error states?
9. **`progress.md` entry:** Does the staged diff include a new entry?
10. **`.gitattributes` present:** Does the repo have `progress.md merge=union`?

## Communication
- **Be concise.** Lead with the answer or action.
- **Show, don't tell.** Include code snippets, commands, or file paths.
- **Progress updates:** For multi-step tasks, report after each step.
- **Flag blockers immediately.** Don't silently struggle.
- **No em dashes.** Do not use em dashes in any written output. Use commas, parentheses, colons, or semicolons instead.

## Multi-Session Continuity
When picking up work from a previous session: read `context.md`, check git log/status, check for open PRs, verify the environment. See `guidance/multi-session.md` for the full checklist and the `--refresh` command.

## Session Wrap-Up
**Before ending any session where you wrote or changed code**, complete all 7 steps: update context.md, update progress.md, commit, push, verify clean status, post to Discord, update completed-work.md. See `guidance/session-wrapup.md` for the full procedure.

## Deployment
Infer deploy commands from repo config. See `guidance/deployment.md` for pre-deploy and post-deploy checklists.

## Maintaining This File
**Keep `agent.md` under 200 lines.** This file is fetched at the start of every session (including Cowork, which has limited context). It should contain only core rules and concise summaries with pointers to guidance files. When adding new guidance:
- If the content is more than 5-10 lines of procedure, create a new `guidance/<topic>.md` file and add a 1-2 line summary + pointer here.
- Never inline detailed procedures, code blocks longer than 5 lines, or step-by-step checklists into this file.
- Add the new guidance file to the index below and to `CLAUDE.md`.

## Guidance File Index
Load these on-demand based on the current task:
- `guidance/testing.md` -- writing or running tests
- `guidance/debugging.md` -- diagnosing issues
- `guidance/code-review.md` -- before committing or opening PRs
- `guidance/dependencies.md` -- adding or updating packages
- `guidance/git-workflow.md` -- branching, PRs, merge procedures
- `guidance/context-progress.md` -- context.md and progress.md specs
- `guidance/discord-integration.md` -- Discord posting, threading, coordination
- `guidance/auto-posting.md` -- writing style, multi-destination design
- `guidance/session-wrapup.md` -- end-of-session checklist
- `guidance/multi-session.md` -- continuity and `--refresh` command
- `guidance/deployment.md` -- deploy checklists
- `guidance/session-lifecycle.md` -- ephemerality, output design, crash recovery
- `guidance/resource-awareness.md` -- server resource checks
- `guidance/process-hygiene.md` -- spawned processes, temp files, port conflicts
- `guidance/operational-safety.md` -- self-deploy loops, restart storms, hook loops
- `guidance/ab-testing.md` -- claude-bakeoff A/B testing
- `guidance/wordpress-auto-posting.md` -- WordPress hook setup
- `guidance/auth-basepath.md` -- authentication and base path patterns
- `guidance/local-worker-bridge.md` -- local worker bridge post-mortem
