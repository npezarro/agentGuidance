<!-- agent.md v4.2.0 | Last updated: 2026-08-03 -->
# Global Agent Rules

> **THIS IS A PUBLIC REPOSITORY.** Never commit secrets, credentials, API keys, tokens, webhook URLs, passwords, private IPs, internal hostnames, `.env` contents, or any other sensitive information.

## Identity & Defaults
- **Stack:** JavaScript / Node.js (ES modules, modern syntax), React (functional components + hooks, Tailwind), HTML/CSS, Google Apps Script, Tampermonkey userscripts. Python for scripting, plus Bash and Markdown.
- **Package managers:** npm (preferred); pip when Python is required.
- **GitHub:** github.com/npezarro (personal repos, not production services).

## Core Principles
> `guidance/ESSENTIAL.md` is always co-loaded with this file. Its rules (learning capture, guidance-updates-to-repo-files, verify before asserting, test before reporting, gather context first, mistake postmortem, self-service) are NOT repeated here; each rule lives in exactly one place.
- **Plan before coding.** Outline approach, files affected, risks. Confirm before implementing.
- **Ask only when it changes the work.** Make routine judgment calls yourself; stop and ask when two readings of the prompt would produce materially different work. Never invent requirements to paper over a gap.
- **Validate incrementally.** Run `npm run build` after changes (`npx jest` where tests exist). Never commit broken code.
- **Targeted edits only.** Precise insertions and replacements, not full-file overwrites.
- **Diagnose before retrying.** Understand *why* before re-running. No blind retry loops.
- **Always push to GitHub.** If it's not on GitHub, it doesn't exist. Use `llm-tasks` for deliverables without a home repo.
- **Fall back to page-reader for JS-rendered pages.** WebFetch empty/broken? See `guidance/browser-page-reader.md`. Never skip a shared link; if all methods fail, say so explicitly.
- **No external posting without explicit instruction.** Building features is fine; calling endpoints is not.
- **Work in a git worktree for multi-edit work in `~/repos`.** `EnterWorktree` if the session is rooted in that repo; otherwise (cwd is not a repo, or you span several) `git -C <repo> worktree add .claude/worktrees/<n> -b <n>` and edit via that path. Merge to the default branch and push before you stop. Several sessions share one checkout per repo, and a worktree is what makes a stage-everything commit safe *by construction* instead of merely guarded. Skip it for read-only work, one-file edits, and ops (deploys, VM admin). Deploys read the canonical checkout, so merge and push before deploying. Details: `guidance/concurrent-sessions.md`.

## Code Standards
- **Match existing patterns.** Read `package.json`, config files, and surrounding code first.
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
- **Large outputs go to files.** Write lengthy content (analyses, drafts, guides) to a `.md` file in the relevant repo, not just conversation output. **This includes subagent return values:** persist a detailed subagent report to a file in the same turn, not only the synthesis you distilled from it. Chat is not storage; a report that only ever appeared in a response is lost.
- **Nick dictates via Wispr Flow.** A stray leading lowercase letter (often `v`) at the very start of a message is a dictation artifact, not content: ignore it. Dictated messages carry transcription slips (homophones, dropped/merged words, missing punctuation); read for intent, not literal text, and prefer a near-homophone that makes the sentence coherent. Ask only if a slip makes the actual directive genuinely ambiguous.

## Guidance Files
`guidance/INDEX.md` lists every on-demand guidance file and when to load it. It is generated from each file's `Load when:` header and injected separately at SessionStart, so it is already in context; read it there rather than opening it. `MANIFEST.md` holds the full catalog, including the cold files the index omits.

## Maintaining This File
**Keep `agent.md` under 100 lines.** Universal behavioral rules only; project-specific rules belong in the project's CLAUDE.md. Adding a guidance file costs nothing here: write it with a `Load when:` header, run `scripts/gen-manifest.sh`, commit the regenerated `MANIFEST.md` and `guidance/INDEX.md`. See `MANIFEST.md` for the function-to-source map and the cold-file list.
