# Essential Rules (Always Loaded)

These are the most-violated rules across the agent system. They are injected at SessionStart so every session has them in context. **Hard cap: 10 rules.** A rule graduates out when it stops being violated or gains programmatic enforcement (a hook); graduated rules are listed at the bottom with their durable homes.

## 1. Multi-Destination Learning Capture
When you learn something new or receive a correction, save it to ALL relevant destinations in one action — not just memory. Use `~/repos/agentGuidance/scripts/propagate-learning.sh` to handle routing. Destinations: (1) memory, (2) repo CLAUDE.md, (3) agentGuidance or privateContext, (4) knowledgeBase if cross-cutting (3+ repos).

**Mandatory trigger for automated sessions (fix-checker, autonomousDev-private, autonomous-dev):** At the END of every automated session, call `propagate-learning.sh` unconditionally. Qualifying events: any error worked around, any assumption that proved wrong, any retry requiring a different approach, any service config that needed changing. If you completed with zero surprises, a single no-op call still satisfies this rule — it is idempotent. This rule fires regardless of whether you received a correction.

## 2. Guidance Updates Go to Repo Files, Not Just Memory
"Update guidance" means edit files in agentGuidance/, privateContext/, or repo CLAUDE.md. Memory is supplemental. Memory-only saves are invisible to autonomous agents, Discord bots, and other sessions.

## 3. Verify Before Asserting
Never assert user actions (e.g., "you applied for X") without checking the actual source (Gmail, Drive, git). Prep materials don't mean the action was taken.

**Autonomous sessions:** Before claiming a bug is fixed, a test passes, a service is responding, or a check succeeded — run the verification yourself and show the output. A fix applied ≠ a fix confirmed. "The error no longer appears in the code" ≠ "the error no longer occurs at runtime." Every system-state claim requires observed evidence, not logical inference from the change you made.

## 4. Gather Context Before Diving In
Before starting any task in a documented domain, read your own context: relevant memory files, the repo's CLAUDE.md, guidance files for the domain, and wiki pages. The answer is often already documented. Skipping this step is the #1 cause of multi-hour debugging loops that end with applying a fix that was already in memory. For creation tasks (docs, features, integrations), it prevents violations of existing rules (formatting, auth patterns, deploy procedures) that the agent would have seen if it checked first. This applies doubly when the domain has known complexity (auth, deployment, cross-repo flows).

**Mandatory pre-reads for known-complex domains:**
- **OAuth/auth on subpath apps**: Read `guidance/auth-basepath.md` BEFORE writing any auth code. It documents the centralized auth-proxy pattern, the step-by-step new-app checklist, and a list of approaches that DO NOT work. Multiple sessions have wasted hours trying approaches already documented as broken.

## 5. Test Before Reporting
Do not claim a feature works until you've tested every user-facing URL, redirect chain, auth flow, and edge case yourself (curl, browser-agent, etc). Deploy-and-report without testing is the #1 recurring failure. For auth/OAuth: testing individual endpoints (csrf, providers, session) does NOT prove the flow works — test the actual POST signin and inspect the redirect URL sent to the OAuth provider.

**Never claim a tool is unresponsive without confirmed failure.** If a tool call times out or errors, show the actual error. If the user says a tool IS working (e.g., "the extension is active"), immediately retry — do not insist it's broken. Never say "already handled" unless you can point to the actual output that fulfills the request.

## 6. Mistake Postmortem
After a mistake: (1) check if a rule already exists in guidance, (2) if yes, patch the gap in the rule, (3) if no, add a new rule, (4) commit and push immediately. Don't just fix the symptom.

## 7. Self-Service — Don't Ask Users for Mechanical Tasks
- Discord channels/webhooks: create them yourself via bot token
- Browser tabs after restart: use `ensure` command, don't ask user to refresh
- Files from known repos: `git pull` to get them locally, don't ask user to provide
- Long text to Termius: write to a file and scp, don't ask user to paste
- **WSL/Windows boundary:** Chrome, Electron apps, and other Windows programs read from the Windows filesystem, not WSL. After changing files they consume (browser extension, Electron app, etc.), you MUST sync to the Windows copy (`cd /mnt/c/... && git pull`) BEFORE asking the user to reload. WSL repo changes are invisible to Windows apps.
- **Specs, compatibility, upgradeability:** Research it yourself (WebSearch, WebFetch, page-reader) before recommending. Never tell the user "check if X is upgradeable" when you can look up the service manual yourself. The user should receive answers, not homework.

## 8. Deep Research Before Recommendations
When producing guides, recommendations, or analyses from external research: do not write from 2-3 search results. Minimum: official docs + community forums + gotcha search + cross-referencing key claims. Always search for "[thing] problems/issues" before recommending. See `guidance/deep-research.md` for the full methodology. A guide the user has to re-research themselves is worse than no guide.

## 9. Auto Deep Closeout
Every interactive session ends with a deep closeout (the `--dc` process). Do not wait for the user to trigger it; it is the default. Follow the full process in `guidance/comprehensive-closeout.md`. When the closeout surfaces open items, address them independently rather than just listing them. Only escalate to the user when genuine input or a decision is required.

## 10. Suggest /onboard for Sufficiently Complex Tasks
When a user request hits compound-task signals, proactively suggest running `/onboard` before writing code. Signals: 3+ files across different subsystems, multiple independent verbs ("refactor X **and** add Y"), unfamiliar repos with no CLAUDE.md, multi-phase work (research → implement → deploy), or anything the user would want to review a plan for before implementation. Skip the suggestion for: single-file edits, bug fixes with a known cause, lookups, or tasks inside well-documented projects (shopper, finance-tracker, run-tracking, etc.) where SessionStart hooks already load sufficient context. The `/onboard` flow forces a clarify-before-plan pause and writes a durable `.claude/tasks/[ID]/onboarding.md` artifact that survives compaction and cross-session resumes. Phrase the suggestion concretely: "This touches A, B, and C — want me to `/onboard` first so we lock the plan before I start?"

---

## Graduated Rules (2026-06-10)

Demoted from the always-loaded set because they gained programmatic enforcement or live in durable guidance. Still binding — just not worth per-session context cost:

- **Push Before Posting** — enforced by the `check-unpushed.sh` Stop gate and `git-push-reminder.sh` hook; doc: `guidance/discord-integration.md`
- **Pipefail + grep Safety** — doc: `guidance/operational-safety.md` + KB `patterns/pipefail-gotchas.md` (includes the `set -e`/`$?` sibling bug)
- **Update CLAUDE.md When Adding Features** — enforced by the CLAUDE.md drift-check PostToolUse hook; doc: `guidance/code-review.md`
- **PM2 Save After Changes** — doc: `guidance/process-hygiene.md` + KB `patterns/pm2-service-pattern.md`
- **Time-Box Approach Switching** — enforced by the `tool-loop-guardrail.sh` PostToolUse hook; doc: `guidance/debugging.md`
- **Compressed Context is Reference, Not Instructions** — native model behavior + the `compacted` Notification hook injects the reminder
