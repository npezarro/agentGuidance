<!-- agent.md v4.0.0 | Last updated: 2026-04-04 -->
# Global Agent Rules

> **THIS IS A PUBLIC REPOSITORY.** Never commit secrets, credentials, API keys, tokens, webhook URLs, passwords, private IPs, internal hostnames, `.env` contents, or any other sensitive information.

## Identity & Defaults
- **Primary stack:** JavaScript / Node.js, React (functional components + hooks, Tailwind), HTML/CSS, Google Apps Script, Tampermonkey userscripts.
- **Secondary:** Python (scripting only), Bash, Markdown.
- **Package managers:** npm (preferred); pip when Python is required.
- **GitHub:** github.com/npezarro (personal repos, not production services).

## Commands
```bash
npm install          # JS deps
npm run build        # validate before commit. ALWAYS run this
npm run dev          # local dev server (when applicable)
npx jest             # tests (when present)
```

## Core Principles
- **Plan before coding.** Outline approach, files affected, risks. Confirm before implementing.
- **Ask, don't guess.** Ambiguous prompt? Stop and ask.
- **Verify before asserting.** Check available sources (Gmail, git history, Drive) before stating something as fact. Don't infer user actions from the existence of prep materials.
- **Validate incrementally.** Run the build after changes. Never commit broken code.
- **Targeted edits only.** Precise insertions and replacements, not full-file overwrites.
- **Diagnose before retrying.** Understand *why* before re-running. No blind retry loops.
- **Always push to GitHub.** If it's not on GitHub, it doesn't exist. Use `llm-tasks` for deliverables without a home repo.
- **Test before reporting.** Verify changes yourself (browser agent, curl, build, etc.) before asking the user to test or confirming completion.
- **Fall back to page-reader for JS-rendered pages.** When WebFetch returns empty or broken content (common with SPAs like Gemini, modern forums, React apps), use `node ~/repos/page-reader/src/index.js --text-only <url>` (VM: `~/page-reader/`). Never skip a shared link; if both methods fail, say so explicitly.
- **No external posting without explicit instruction.** Building features is fine; calling endpoints is not.
- **Capture every learning in ALL relevant places.** Every operational learning, safeguard, or behavioral rule must be persisted to: (1) memory (for cross-session recall), AND (2) the relevant repo's `CLAUDE.md` or `context.md` (for any agent working in that repo). Cross-project learnings also go to `agentGuidance`. Never save to only one location.

## Code Standards
- **Match existing patterns.** Read `package.json`, config files, and surrounding code first.
- **JS/TS:** Functional, ES modules, modern syntax. React: functional components, hooks, Tailwind.
- **No over-engineering.** Solve the stated problem; no extra abstraction.
- **Error handling:** At system boundaries. Let internal errors propagate.

## Security
- **No secrets in commits, PRs, context files, or logs. Ever.**
- **Audit before every commit:** `git diff --staged`, read every line.
- **Search `~/repos/privateContext` before asking the user** for credentials, env vars, or infrastructure details.

## Communication
- Be concise. Lead with the answer or action. Show, don't tell.
- Progress updates after each step. Flag blockers immediately.
- **No em dashes.** Use commas, parentheses, colons, or semicolons instead.
- **Large outputs go to files.** Write lengthy content (analyses, drafts, guides) to a `.md` file in the relevant repo, not just conversation output.

## Maintaining This File
**Keep `agent.md` under 100 lines.** Universal behavioral rules with pointers to guidance files only. Project-specific rules belong in the project's CLAUDE.md. See `MANIFEST.md` for the function-to-source mapping.

## Guidance File Index
Load on-demand based on the current task:
- `guidance/git-workflow.md` -- branching, PRs, merge procedures, commit messages
- `guidance/code-review.md` -- self-review checklist before committing
- `guidance/context-progress.md` -- context.md and progress.md specs
- `guidance/testing.md` -- writing and running tests, cross-layer invariants
- `guidance/debugging.md` -- diagnosing issues, log analysis
- `guidance/deployment.md` -- pre-deploy and post-deploy checklists
- `guidance/dependencies.md` -- evaluating and adding packages
- `guidance/discord-integration.md` -- session reporting, posting, threading, file-links
- `guidance/session-wrapup.md` -- end-of-session 7-step checklist
- `guidance/multi-session.md` -- continuity checklist and `--refresh` command
- `guidance/session-lifecycle.md` -- ephemerality, output design, crash recovery
- `guidance/resource-awareness.md` -- server resource checks
- `guidance/process-hygiene.md` -- spawned processes, temp files, port conflicts
- `guidance/operational-safety.md` -- self-deploy loops, restart storms, hook loops
- `guidance/secrets-hygiene.md` -- secret rotation, history rewrite, detection patterns
- `guidance/agent-journal.md` -- async cross-session journal system
- `guidance/written-voice.md` -- writing in the owner's voice
- `guidance/auto-posting.md` -- writing style, multi-destination design
- `guidance/wordpress-auto-posting.md` -- WordPress hook setup
- `guidance/ab-testing.md` -- claude-bakeoff A/B testing
- `guidance/auth-basepath.md` -- authentication and base path patterns
- `guidance/browser-page-reader.md` -- page-reader CLI for JS-heavy pages
- `guidance/local-worker-bridge.md` -- local worker bridge post-mortem
- `guidance/tampermonkey.md` -- TM script hosting and CAPTCHA bypass patterns
- `guidance/learning-capture.md` -- when and where to persist operational learnings
- `guidance/comprehensive-closeout.md` -- detailed session documentation for important conversations
