# Global Agent Rules — Nicholas Pezarro

## Identity & Defaults
- **Role:** Senior Product Manager building prototypes and productivity tools.
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
- Atomic commits — message explains **why**, not just what.
- Before committing:
  1. `git status` — verify no unintended files staged.
  2. `git diff` — review the actual changes.
  3. Confirm no `.env`, secrets, or key files are included.
- Push: `git push -u origin HEAD`. Retry network failures up to 4× with backoff (2s, 4s, 8s, 16s). Do not retry auth failures.
- Create a PR after pushing:
  ```
  gh pr create --title "<task>" --body "<context>"
  ```
- If `gh` is not available or not authenticated, provide the manual PR URL:
  ```
  https://github.com/<owner>/<repo>/pull/new/<branch-name>
  ```
- Do **not** enable auto-merge unless explicitly asked.

## Context File (`context.md`)
Maintain at the repo root. Read on session start; update before every push.

```
# context.md
Last Updated: YYYY-MM-DD — one-line summary
Current State: what works, what's deployed, known issues
Recent Changes: what changed and why (keep brief)
Open Work: blockers, unfinished tasks, decisions needed
Environment Notes: deploy target, process manager, ports, SSH user, config file paths
Active Branch: current working branch name
```

**Never include:** credentials, API keys, tokens, passwords, or `.env` contents.

**Environment Notes must include** (when applicable):
- SSH user and hostname
- PM2 process name and port
- Web server config file path (e.g., Apache VirtualHost location)
- Base path if deployed to a subdirectory
- Database file path

This is how the next agent picks up where you left off. Be thorough.

## Code Standards
- **Match existing patterns.** Read `package.json`, config files, and surrounding code before writing anything. Do not introduce new frameworks, ORMs, or styling approaches without explicit approval.
- **JS/TS style:** Functional, ES modules, modern syntax (async/await, optional chaining, destructuring). React: functional components, hooks, Tailwind — no class components.
- **Logging:** Use `console.log` / `console.error` liberally in scripts and prototypes. For deployed or user-facing code, log errors and key state transitions only.
- **No over-engineering.** Solve the stated problem. Don't add abstraction layers, feature flags, or refactors beyond what was asked.

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
- No secrets in commits, PRs, context files, or logs. Ever.
- Environment-specific values belong in `.env` or local config, never in committed code.

## Deployment
- Infer deploy commands from repo config (GitHub Actions, scripts, `context.md`).
- **Pre-deploy checklist:**
  1. All changes committed and pushed via PR.
  2. Build succeeds locally.
  3. `context.md` updated with deployment intent.
  4. No secrets exposed in repository history.
