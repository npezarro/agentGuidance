# Global Agent Rules

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
- No secrets in commits, PRs, context files, or logs. Ever.
- Environment-specific values belong in `.env` or local config, never in committed code.

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
