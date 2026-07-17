<!-- agent.md v4.1.1 | Last updated: 2026-07-16 -->
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
> `guidance/ESSENTIAL.md` is always co-loaded with this file. Its rules (learning capture, guidance-updates-to-repo-files, verify before asserting, test before reporting, gather context first, mistake postmortem, self-service) are NOT repeated here; each rule lives in exactly one place.
- **Plan before coding.** Outline approach, files affected, risks. Confirm before implementing.
- **Ask, don't guess.** Ambiguous prompt? Stop and ask.
- **Validate incrementally.** Run the build after changes. Never commit broken code.
- **Targeted edits only.** Precise insertions and replacements, not full-file overwrites.
- **Diagnose before retrying.** Understand *why* before re-running. No blind retry loops.
- **Always push to GitHub.** If it's not on GitHub, it doesn't exist. Use `llm-tasks` for deliverables without a home repo.
- **Fall back to page-reader for JS-rendered pages.** WebFetch empty/broken? See `guidance/browser-page-reader.md`. Never skip a shared link; if all methods fail, say so explicitly.
- **No external posting without explicit instruction.** Building features is fine; calling endpoints is not.

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
- **Nick dictates via Wispr Flow.** A stray leading lowercase letter (often `v`) at the very start of a message is a dictation artifact, not content: ignore it. Dictated messages carry transcription slips (homophones, dropped/merged words, missing punctuation); read for intent, not literal text, and prefer a near-homophone that makes the sentence coherent. Ask only if a slip makes the actual directive genuinely ambiguous.

## Maintaining This File
**Keep `agent.md` under 100 lines.** Universal behavioral rules with pointers to guidance files only. Project-specific rules belong in the project's CLAUDE.md. See `MANIFEST.md` for the function-to-source mapping.

## Guidance File Index
**Always loaded at SessionStart:** `guidance/ESSENTIAL.md` (top-10 most-violated rules).
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
- `guidance/goal-conditions.md` -- /goal for headless runners: mission-file pattern, condition rules, BLOCKED escape hatch
- `guidance/secrets-hygiene.md` -- secret rotation, history rewrite, detection patterns
- `guidance/agent-journal.md` -- async cross-session journal system
- `guidance/written-voice.md` -- writing in the owner's voice
- `guidance/auto-posting.md` -- writing style, multi-destination design
- `guidance/wordpress-auto-posting.md` -- WordPress hook setup
- `guidance/ab-testing.md` -- claude-bakeoff A/B testing
- `guidance/auth-basepath.md` -- authentication and base path patterns
- `guidance/browser-page-reader.md` -- page-reader CLI for JS-heavy pages
- `guidance/warehouse-analytics.md` -- Snowflake/warehouse pull → DuckDB analysis → publish; auth ladder + cost gate + publish gotchas
- `guidance/local-worker-bridge.md` -- local worker bridge post-mortem
- `guidance/tampermonkey.md` -- TM script hosting and CAPTCHA bypass patterns
- `guidance/learning-capture.md` -- when and where to persist operational learnings
- `guidance/learning-agent.md` -- hourly learning review: passes, staging, PR workflow
- `guidance/comprehensive-closeout.md` -- detailed session documentation for important conversations
- `guidance/stop-hook-safety.md` -- tiered stop hook classification, guard library, Tier 3 recursion prevention
- `guidance/mcp-tools.md` -- MCP tool provider selection (Claude AI vs piotr google-drive)
- `guidance/prior-work-lookup.md` -- finding past conversations and prior work
- `guidance/research-quality.md` -- curating high-quality references and study resources
- `guidance/deep-research.md` -- research depth and methodology before producing guides or recommendations
- `guidance/fact-checking.md` -- mandatory search-verification of external actionable claims (prices, eligibility rules, offers) before asserting
- `guidance/provenance.md` -- mark Claude-generated facts vs Nick's own writing; capture every source to the private sourceLibrary repo (source-registry.sh)
- `guidance/wiki-consultation.md` -- when and how to consult knowledgeBase wiki pages
- `guidance/repo-creation.md` -- checklist for new repos: cross-cutting guidance incorporation, CLAUDE.md structure
- `guidance/public-app-isolation.md` -- siloed alt account pattern for public-facing apps with untrusted input
- `guidance/when-to-fan-out.md` -- when to spawn subagents (Task fan-out / parallel bash / Workflow) vs stay single-agent; concurrency-safe 3-phase pattern
- `guidance/synthetic-panel.md` -- advisory synthetic-user feedback on user-facing changes; fail-open contract, panel-check.sh usage
- `guidance/opus-fable-parity.md` -- validated instruction layer closing the Opus 4.8 → Fable 5 behavioral gap; inject into Opus pipelines needing Fable-grade rigor (requires ≥45-turn budget)
