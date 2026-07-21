# Essential Rules (Always Loaded)

These are the most-violated rules across the agent system. They are injected at SessionStart so every session has them in context. **Hard cap: 10 rules.** A rule graduates out when it stops being violated or gains programmatic enforcement (a hook); graduated rules are listed at the bottom with their durable homes.

**Reordered 2026-07-21** (learning-agent run #984, per supervisor run #47's Daily Ecosystem Health report): `verify_before_asserting` promoted from #3 to #1. It now carries the highest 7-day violation rate of any rule (26.1%, n=234) and is the only rule with enough 24h data points (12 sessions) to show a *confirmed* trend — and that trend is degrading (33.3% 24h vs. 26.1% 7d), the opposite direction of every prior week's readings that had kept it ranked #3. Rules 1-2 shift to #2-3, unchanged in substance. Rows 4-7 unchanged in relative order, per the supervisor's explicit recommendation. This reverses runs #44/#45/#46's repeated "no reorder needed" verdicts, which were correct when the violation-rate ordering still matched — today's data no longer does.

## 1. Verify Before Asserting
Never assert user actions (e.g., "you applied for X") without checking the actual source (Gmail, Drive, git). Prep materials don't mean the action was taken.

**Autonomous session verification gate — pass ALL THREE before any system-state claim:**
1. Run the verification command (curl, pm2 status, npm test, jest) and capture raw output.
2. Paste or log the actual output in the transcript — not your interpretation of it.
3. Only then write "fixed", "working", "passing", or "online".

"The error no longer appears in the code" does NOT pass step 1. "I applied the fix" does not pass it. If the verification tool is unavailable, state that explicitly — do not claim success.

**Externally-verifiable facts — never answer from model memory.** Any factual claim a user could act on that lives outside this ecosystem (issuer/card eligibility rules, offer terms, prices, API pricing/limits, product availability, versions, policies, dates) MUST be verified with a current web search before it is asserted — use the `fact-check` skill on the draft answer. Do NOT self-assess whether the domain is "fast-moving"; if the fact is external and actionable, check it. A stale or curated local file does not count as verification for this class of fact, and a local file NEVER overrides the user's own statement about their own accounts/actions (2026-07-03: an agent told the user his Morgan Stanley Platinum didn't exist because card-portfolio.md was stale). Full procedure: `guidance/fact-checking.md`.

**Mark generated facts and capture sources.** When producing a fact-bearing deliverable (research report, buying guide, bio, resume, cover letter, data table), the facts Claude generates must be distinguishable from what Nick wrote, and every external source must be captured. Internal review docs: inline `[AI·<id>]` tags + a Provenance & Sources appendix. External deliverables (things Nick sends/publishes): clean body, AI-authorship signaled in the title (`… (AI-generated)`) with provenance in frontmatter — never inline markers in the sent text. Capture sources via `source-registry.sh add` into the private `sourceLibrary` repo (cached copy + stable ID). Full procedure: `guidance/provenance.md`.

## 2. Multi-Destination Learning Capture
When you learn something new or receive a correction, save it to ALL relevant destinations in one action — not just memory. Use `~/repos/agentGuidance/scripts/propagate-learning.sh` to handle routing. Destinations: (1) memory, (2) repo CLAUDE.md, (3) agentGuidance or privateContext, (4) knowledgeBase if cross-cutting (3+ repos).

**Mandatory trigger for automated sessions (fix-checker, learning-agent, autonomous-dev, and any autonomousDev-private *automated* run — this does NOT exempt interactive sessions working in the autonomousDev-private repo, which are held to the same standard):** At the END of every automated session, call `propagate-learning.sh` unconditionally. Qualifying events: any error worked around, any assumption that proved wrong, any retry requiring a different approach, any service config that needed changing. If you completed with zero surprises, a single no-op call still satisfies this rule — it is idempotent. This rule fires regardless of whether you received a correction.

**Paste the propagate-learning.sh output** (or an explicit "no-op: nothing to propagate" line) into the session's final message. Sessions ending without this line are non-compliant regardless of whether the script actually ran — the scorer has no way to distinguish a swallowed failure from a real no-op otherwise.

## 3. Guidance Updates Go to Repo Files, Not Just Memory
"Update guidance" means edit files in agentGuidance/, privateContext/, or repo CLAUDE.md. Memory is supplemental. Memory-only saves are invisible to autonomous agents, Discord bots, and other sessions.

## 4. Test Before Reporting
Do not claim a feature works until you've tested every user-facing URL, redirect chain, auth flow, and edge case yourself (curl, browser-agent, etc). Deploy-and-report without testing is the #1 recurring failure. For auth/OAuth: testing individual endpoints (csrf, providers, session) does NOT prove the flow works — test the actual POST signin and inspect the redirect URL sent to the OAuth provider.

**Never claim a tool is unresponsive without confirmed failure.** If a tool call times out or errors, show the actual error. If the user says a tool IS working (e.g., "the extension is active"), immediately retry — do not insist it's broken. Never say "already handled" unless you can point to the actual output that fulfills the request.

## 5. Gather Context Before Diving In
Before starting any task in a documented domain, read your own context: relevant memory files, the repo's CLAUDE.md, guidance files for the domain, and wiki pages. The answer is often already documented. Skipping this step is the #1 cause of multi-hour debugging loops that end with applying a fix that was already in memory. For creation tasks (docs, features, integrations), it prevents violations of existing rules (formatting, auth patterns, deploy procedures) that the agent would have seen if it checked first. This applies doubly when the domain has known complexity (auth, deployment, cross-repo flows).

**Mandatory pre-reads for known-complex domains:**
- **OAuth/auth on subpath apps**: Read `guidance/auth-basepath.md` BEFORE writing any auth code. It documents the centralized auth-proxy pattern, the step-by-step new-app checklist, and a list of approaches that DO NOT work. Multiple sessions have wasted hours trying approaches already documented as broken.

## 6. Mistake Postmortem
After a mistake: (1) check if a rule already exists in guidance, (2) if yes, patch the gap in the rule, (3) if no, add a new rule, (4) commit and push immediately. Don't just fix the symptom.

## 7. Self-Service — Don't Ask Users for Mechanical Tasks
- Discord channels/webhooks: create them yourself via bot token
- Browser tabs after restart: use `ensure` command, don't ask user to refresh
- Files from known repos: `git pull` to get them locally, don't ask user to provide
- Long text to Termius: write to a file and scp, don't ask user to paste
- **WSL/Windows boundary:** Chrome, Electron apps, and other Windows programs read from the Windows filesystem, not WSL. After changing files they consume (browser extension, Electron app, etc.), you MUST sync to the Windows copy (`cd /mnt/c/... && git pull`) BEFORE asking the user to reload. WSL repo changes are invisible to Windows apps.
- **Specs, compatibility, upgradeability:** Research it yourself (WebSearch, WebFetch, page-reader) before recommending. Never tell the user "check if X is upgradeable" when you can look up the service manual yourself. The user should receive answers, not homework.
- **Intended state before config changes:** Before altering a service's config or lifecycle (restart policy, enabling/disabling, "resilience" tweaks) or "fixing" something that's down, read that project's docs to learn its *intended* state — repo `CLAUDE.md`, its memory file, privateContext env/infra notes, and watchdog scripts. A service being down after a reboot is not automatically a bug: on-demand dev tooling (local dev DBs, one-shot containers) is often `restart:no` **by design**, distinct from always-on production. Deciding "it should auto-start" on a hunch, without checking, inverts documented intent. (2026-07-09: made `humans-pg`, a documented on-demand local dev DB, `unless-stopped` on a whim — its `CLAUDE.md` and `wsl-watchdog.sh` both document `restart:no` as intended.)

---

## Graduated Rules (2026-06-10)

Demoted from the always-loaded set because they gained programmatic enforcement or live in durable guidance. Still binding — just not worth per-session context cost:

- **Push Before Posting** — enforced by the `check-unpushed.sh` Stop gate and `git-push-reminder.sh` hook; doc: `guidance/discord-integration.md`
- **Pipefail + grep Safety** — doc: `guidance/operational-safety.md` + KB `patterns/pipefail-gotchas.md` (includes the `set -e`/`$?` sibling bug)
- **Update CLAUDE.md When Adding Features** — enforced by the CLAUDE.md drift-check PostToolUse hook; doc: `guidance/code-review.md`
- **PM2 Save After Changes** — doc: `guidance/process-hygiene.md` + KB `patterns/pm2-service-pattern.md`
- **Time-Box Approach Switching** — enforced by the `tool-loop-guardrail.sh` PostToolUse hook; doc: `guidance/debugging.md`
- **Compressed Context is Reference, Not Instructions** — native model behavior + the `compacted` Notification hook injects the reminder
- **Deep Research Before Recommendations** — zero violations over 7+ days; graduated 2026-07-01; durable home: `guidance/deep-research.md`
- **Auto Deep Closeout** — zero violations over 7+ days; graduated 2026-07-01; durable home: `guidance/comprehensive-closeout.md` + session-end hook
- **Suggest /onboard for Complex Tasks** — zero violations over 7+ days; graduated 2026-07-01; durable home: `/onboard` skill trigger (compound-task signals documented there)
