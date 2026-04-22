# Essential Rules (Always Loaded)

These are the most-violated rules across the agent system. They are injected at SessionStart so every session has them in context. Each rule here has been violated 3+ times despite being documented elsewhere.

## 1. Test Before Reporting
Do not claim a feature works until you've tested every user-facing URL, redirect chain, auth flow, and edge case yourself (curl, browser-agent, etc). Deploy-and-report without testing is the #1 recurring failure. For auth/OAuth: testing individual endpoints (csrf, providers, session) does NOT prove the flow works — test the actual POST signin and inspect the redirect URL sent to the OAuth provider.

## 2. Multi-Destination Learning Capture
When you learn something new or receive a correction, save it to ALL relevant destinations in one action — not just memory. Use `~/repos/agentGuidance/scripts/propagate-learning.sh` to handle routing. Destinations: (1) memory, (2) repo CLAUDE.md, (3) agentGuidance or privateContext, (4) knowledgeBase if cross-cutting (3+ repos).

## 3. Push Before Posting
Always `git commit && git push` BEFORE posting links to Discord (#file-links, #cli-interactions). URLs don't resolve until the push lands.

## 4. Self-Service — Don't Ask Users for Mechanical Tasks
- Discord channels/webhooks: create them yourself via bot token
- Browser tabs after restart: use `ensure` command, don't ask user to refresh
- Files from known repos: `git pull` to get them locally, don't ask user to provide
- Long text to Termius: write to a file and scp, don't ask user to paste
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

## 11. Gather Context Before Debugging
Before diving into a fix, read your own context: relevant memory files, the repo's CLAUDE.md, guidance files for the domain, and wiki pages. The answer is often already documented. Skipping this step is the #1 cause of multi-hour debugging loops that end with applying a fix that was already in memory. This applies doubly when the domain has known complexity (auth, deployment, cross-repo flows).

## 12. Time-Box Approach Switching
If you've tried 2+ variations of the same approach without progress (e.g., changing a config value back and forth), stop and try a fundamentally different approach. If stuck for 15+ minutes, spawn a debugger agent for fresh analysis. Repeating the same category of fix with different values is brute force, not debugging.
