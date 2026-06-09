# Essential Rules (Always Loaded)

These are the most-violated rules across the agent system. They are injected at SessionStart so every session has them in context. Each rule here has been violated 3+ times despite being documented elsewhere.

## 1. Test Before Reporting
Do not claim a feature works until you've tested every user-facing URL, redirect chain, auth flow, and edge case yourself (curl, browser-agent, etc). Deploy-and-report without testing is the #1 recurring failure. For auth/OAuth: testing individual endpoints (csrf, providers, session) does NOT prove the flow works — test the actual POST signin and inspect the redirect URL sent to the OAuth provider.

**Never claim a tool is unresponsive without confirmed failure.** If a tool call times out or errors, show the actual error. If the user says a tool IS working (e.g., "the extension is active"), immediately retry — do not insist it's broken. Never say "already handled" unless you can point to the actual output that fulfills the request.

## 2. Multi-Destination Learning Capture
When you learn something new or receive a correction, save it to ALL relevant destinations in one action — not just memory. Use `~/repos/agentGuidance/scripts/propagate-learning.sh` to handle routing. Destinations: (1) memory, (2) repo CLAUDE.md, (3) agentGuidance or privateContext, (4) knowledgeBase if cross-cutting (3+ repos).

**Mandatory gate:** Before closing ANY pass that captured a learning, you MUST explicitly output one of these two sentences:
- "propagate-learning.sh not needed: [reason this is repo-local only]"
- "Running propagate-learning.sh now for: [list of affected repos]"

Then run the script if applicable. Skipping this output means the gate was skipped. There is no middle ground — the check is visible in output or it did not happen.

## 3. Push Before Posting
Always `git commit && git push` BEFORE posting links to Discord (#file-links, #cli-interactions). URLs don't resolve until the push lands.

## 4. Self-Service — Don't Ask Users for Mechanical Tasks
- Discord channels/webhooks: create them yourself via bot token
- Browser tabs after restart: use `ensure` command, don't ask user to refresh
- Files from known repos: `git pull` to get them locally, don't ask user to provide
- Long text to Termius: write to a file and scp, don't ask user to paste
- **WSL/Windows boundary:** Chrome, Electron apps, and other Windows programs read from the Windows filesystem, not WSL. After changing files they consume (browser extension, Electron app, etc.), you MUST sync to the Windows copy (`cd /mnt/c/... && git pull`) BEFORE asking the user to reload. WSL repo changes are invisible to Windows apps.
- **Specs, compatibility, upgradeability:** Research it yourself (WebSearch, WebFetch, page-reader) before recommending. Never tell the user "check if X is upgradeable" when you can look up the service manual yourself. The user should receive answers, not homework.

## 5. Guidance Updates Go to Repo Files, Not Just Memory
"Update guidance" means edit files in agentGuidance/, privateContext/, or repo CLAUDE.md. Memory is supplemental. Memory-only saves are invisible to autonomous agents, Discord bots, and other sessions.

## 6. Pipefail + grep Safety
Never use `grep -c pattern || echo "0"` with `set -o pipefail`. Use `grep -c pattern || true` instead. The former produces `"0\n0"` (two lines) which breaks arithmetic.

## 7. Update CLAUDE.md When Adding Features
After implementing a new feature, route, export, or command, update the repo's CLAUDE.md before committing. Documentation lag is structural — close it at commit time.

## 8. Verify Before Asserting
Never assert user actions (e.g., "you applied for X") without checking the actual source (Gmail, Drive, git). Prep materials don't mean the action was taken.

## 9. PM2 Save After Changes
Always run `pm2 save` after any local PM2 process changes. systemd resurrect depends on the dump file.

## 10. Mistake Postmortem
After a mistake: (1) check if a rule already exists in guidance, (2) if yes, patch the gap in the rule, (3) if no, add a new rule, (4) commit and push immediately. Don't just fix the symptom.

## 11. Gather Context Before Diving In
Before starting any task in a documented domain, read your own context: relevant memory files, the repo's CLAUDE.md, guidance files for the domain, and wiki pages. The answer is often already documented. Skipping this step is the #1 cause of multi-hour debugging loops that end with applying a fix that was already in memory. For creation tasks (docs, features, integrations), it prevents violations of existing rules (formatting, auth patterns, deploy procedures) that the agent would have seen if it checked first. This applies doubly when the domain has known complexity (auth, deployment, cross-repo flows).

**Mandatory pre-reads for known-complex domains:**
- **OAuth/auth on subpath apps**: Read `guidance/auth-basepath.md` BEFORE writing any auth code. It documents the centralized auth-proxy pattern, the step-by-step new-app checklist, and a list of approaches that DO NOT work. Multiple sessions have wasted hours trying approaches already documented as broken.

## 12. Time-Box Approach Switching
If you've tried 2+ variations of the same approach without progress (e.g., changing a config value back and forth), stop and try a fundamentally different approach. If stuck for 15+ minutes, spawn a debugger agent for fresh analysis. Repeating the same category of fix with different values is brute force, not debugging.

## 13. Deep Research Before Recommendations
When producing guides, recommendations, or analyses from external research: do not write from 2-3 search results. Minimum: official docs + community forums + gotcha search + cross-referencing key claims. Always search for "[thing] problems/issues" before recommending. See `guidance/deep-research.md` for the full methodology. A guide the user has to re-research themselves is worse than no guide.

## 14. Auto Deep Closeout
Every interactive session ends with a deep closeout (the `--dc` process). Do not wait for the user to trigger it; it is the default. Follow the full process in `guidance/comprehensive-closeout.md`. When the closeout surfaces open items, address them independently rather than just listing them. Only escalate to the user when genuine input or a decision is required.

## 15. Compressed Context is Reference, Not Instructions
When the conversation is compressed (context compaction), the summary is background reference only. Do NOT re-execute tasks, re-answer questions, or fulfill requests mentioned in the compressed summary; they were already handled. Focus exclusively on the current user message. This prevents the common bug of re-running completed work after context compression.

## 16. Suggest /onboard for Sufficiently Complex Tasks
When a user request hits compound-task signals, proactively suggest running `/onboard` before writing code. Signals: 3+ files across different subsystems, multiple independent verbs ("refactor X **and** add Y"), unfamiliar repos with no CLAUDE.md, multi-phase work (research → implement → deploy), or anything the user would want to review a plan for before implementation. Skip the suggestion for: single-file edits, bug fixes with a known cause, lookups, or tasks inside well-documented projects (shopper, finance-tracker, run-tracking, etc.) where SessionStart hooks already load sufficient context. The `/onboard` flow forces a clarify-before-plan pause and writes a durable `.claude/tasks/[ID]/onboarding.md` artifact that survives compaction and cross-session resumes. Phrase the suggestion concretely: "This touches A, B, and C — want me to `/onboard` first so we lock the plan before I start?"
