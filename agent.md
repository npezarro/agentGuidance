<!-- agent.md v3.0.0 | Last updated: 2026-03-26 -->
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
- When in doubt about where a learning belongs, prefer `agentGuidance` (it's read by all sessions) over project-local files.

## Planning & Execution
- **Plan before coding.** For anything beyond a single-file fix, outline the approach (files affected, sequence, risks) and confirm before implementing.
- **Ask, don't guess.** If the prompt is ambiguous or missing constraints, stop and ask immediately.
- **Validate incrementally.** Run the build after changes. Never commit broken code.
- **Targeted edits only.** Do not overwrite entire files. Use precise insertions and replacements. Re-read files post-edit to verify surrounding code integrity.
- **Dry-run first.** Use `--dry-run` for destructive or bulk commands when available.
- **Diagnose before retrying.** If a command fails, understand *why* before re-running. No blind retry loops.
- **Always push to GitHub.** When working on code or producing written materials, commit and push to the relevant repo. The remote is the source of truth.
- **No external posting without explicit instruction.** Never post, submit, register, or publish to external sites or APIs unless the user explicitly asks. Building features that *could* post is fine; actually calling endpoints is not.
- **Research/analysis output goes to `assortedLLMTasks/tasks/`.** When a task produces a written deliverable (not code), save it as a dated markdown file: `~/repos/assortedLLMTasks/tasks/YYYY-MM-DD-topic-slug.md`. Push to GitHub.

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
Run existing tests before and after changes. Write tests for bug fixes and non-trivial logic. For cross-layer changes, write invariant tests that verify the contract between producer and consumer (see `guidance/testing.md` — "Cross-Layer Invariant Tests" section).

## Iteration & Data Quality
When iterating on a deployed app, follow this priority order every turn:
1. **Data correctness > feature completeness > visual polish.** If a feature exists but shows wrong or missing data, fix the data first.
2. **No placeholder data in user-facing UI.** Generic addresses ("94102 area"), missing units ($2.99 without /lb), raw IDs, or "Coming Soon" for features that could work — fix these before adding new features.
3. **Every database record must have required fields at creation time.** Stores need coordinates and real addresses. Prices need units. Don't create records that downstream queries will silently filter out.
4. **Every button must have a meaningful result.** If "Choose This Plan" just shows a toast, it needs a real action (detail view, navigation, etc.).
5. **Verify end-to-end after every change.** TypeScript compiles clean, all tests pass, deploy succeeds, site returns 200.

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

## Private Context & Discord Logs

**Before asking the user for credentials, env vars, API keys, or infrastructure details, search `~/repos/privateContext` first.** It contains everything sensitive that cannot live in public repos. Grep it, read its files, check its scripts. Only ask the user if you've searched and confirmed the information isn't there.

Similarly, **when you're missing context about recent work, decisions, or project state**, check Discord logs via the bot token at `~/.cache/discord-bot-token`. Recent session reports, task completions, and agent journal entries are all posted there.

This is not optional. The owner should never have to answer a question that privateContext or Discord already answers.

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
**Keep `agent.md` under 200 lines.** This file is fetched at the start of every session (including Cowork, which has limited context). It should contain only universal behavioral rules with pointers to guidance files. Project-specific rules belong in the project's CLAUDE.md, not here.

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
- `guidance/browser-page-reader.md` -- page-reader CLI for JS-heavy page content extraction
- `guidance/secrets-hygiene.md` -- secret rotation, history rewrite, detection patterns
- `guidance/job-pipeline.md` -- application materials, resume tailoring, PDF conversion
- `guidance/agent-journal.md` -- async cross-session journal system
- `guidance/written-voice.md` -- writing in the owner's voice
