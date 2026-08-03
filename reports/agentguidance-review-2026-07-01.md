# agentGuidance In-Depth Review: 2026-07-01

Full-repo review (guidance/, hooks/, scripts/, profiles/, claude-agents/, templates/, wiring in `~/.claude/settings.json`). Three parallel review agents plus direct verification of every high-severity claim. Findings below are verified against the actual files; two agent claims were corrected during verification (noted inline).

## Verdict

The system's architecture is sound: slim always-loaded layer (ESSENTIAL.md + agent.md), on-demand guidance files, guarded Stop hooks, programmatic enforcement for graduated rules. The problems are accumulation, not design:

1. **Context budget leaks.** Every session injects ~25KB (~6-7K tokens): ESSENTIAL (6.7KB) + agent.md (6.9KB) + KB index (6.1KB) + WP posts + journal + CLI interactions. ESSENTIAL and agent.md overlap substantially (verify-before-asserting, test-before-reporting, learning capture, self-service all appear in both).
2. **A live noise bug.** The agent-journal SessionStart injection is currently ~80% contentless: trading-agent posts hourly entries whose entire body is the word "discovery". The hook does no content filtering or dedup.
3. **Doc drift.** MANIFEST.md says "24 files" in guidance/; there are 38. agent.md header says last updated 2026-04-04; it has been edited through late June. (Corrected finding: agent.md's guidance INDEX is complete; only MANIFEST is stale.)
4. **Hook bugs.** A handful of real shell bugs, one silent-failure path that defeats the closeout-report rule, and GNU-only constructs (grep -P, flock) that will bite on the Mac OrbStack and any BSD environment.
5. **Repo category mismatch.** A public behavioral-guidance repo also hosts two live cron services (security-scanner: 12MB of logs + state.json churning in the working tree; daily-tldr), supervisor run reports, and a tracked personal job-search log.

## Corrected agent claims (do NOT act on these)

- "agent.md index drift": false. Every guidance file on disk is indexed; ESSENTIAL.md is intentionally listed as auto-loaded.
- "post-closeout.sh blocks session exit": overstated. The settings.json wrapper appends `; exit 0`, so nothing blocks. The real bug is the opposite: it dies silently (see F2).
- "72-second SessionStart worst case": wrong model. Hooks in one event run in parallel; worst-case latency is ~12s (the max single timeout). The real cost is injected context volume, not wall clock.

---

## Findings and proposed changes

### P0: correctness and safety

**F1. Journal injection is mostly noise (live, visible every session).**
`~/.claude/settings.json` SessionStart journal hook pulls 15 messages and prints the first 3 lines of each with no content filter. trading-agent currently posts hourly `[JOURNAL] ... | observation` entries with body "discovery" (it appears to pass the entry type where content belongs).
Fix (two sides): (a) in trading-agent, fix the `journal-post.sh` call arguments; (b) in the SessionStart hook, drop entries whose body after the header is <40 chars, and collapse consecutive same-author entries. Effort: 30 min.

**F2. post-closeout.sh silently never posts when CLOSEOUT_CHANNEL_ID is unset.**
`hooks/post-closeout.sh:21` uses `${CLOSEOUT_CHANNEL_ID:?...}` under `set -euo pipefail`. If the webhook URL is set but the channel ID is not, the script dies; the `; exit 0` wrapper masks it, so closeouts vanish with no signal. This defeats the "visible closeout report" rule.
Fix: replace `:?` with an early `exit 0` plus a one-line stderr warning, and have hook-health-check assert the var is set. Effort: 10 min.

**F3. GNU-only constructs break portability.**
`hooks/auto-file-links.sh:29` (grep -oP), `hooks/scan-context-injection.sh:63` (grep -Pn with Unicode classes), `hooks/compact-memory-index.sh:62` and `scripts/propagate-learning.sh:95` (flock, no availability check). The Mac OrbStack environment (BSD grep) and minimal containers will fail here. compact-memory-index was just made "portable across machines" (25be864) but still assumes flock.
Fix: replace grep -P with grep -E or a python3 one-liner; guard flock with `command -v flock` and an mkdir-lock fallback. Effort: 1 hr.

**F4. tool-loop-guardrail.sh keys on $PPID for session identity.**
`hooks/tool-loop-guardrail.sh:26`. PPID is unreliable across subshells and collides when multiple sessions share a parent.
Fix: parse `session_id` from the hook JSON stdin (already available; stop-hook-guard.sh shows the pattern). Effort: 20 min.

**F5. save-to-wp-repo.sh registers its cleanup trap after mktemp and after an early-exit path.**
`hooks/save-to-wp-repo.sh:40-48`. Early exits leak the temp file.
Fix: move the trap registration to immediately after `set -euo pipefail`. Effort: 5 min.

### P1: context budget and guidance effectiveness

**F6. Deduplicate ESSENTIAL.md vs agent.md (both fully injected every session).**
Overlapping rules: verify-before-asserting, test-before-reporting, learning capture, self-service, plan-before-coding. Proposal: agent.md becomes pure routing (identity, commands, security one-liners, guidance index); every behavioral rule lives in exactly one of ESSENTIAL (always-loaded) or a guidance file (on-demand). Saves an estimated 1-2K tokens per session, every session, across every agent (interactive, autonomousDev, learning-agent, fix-checker, VM #requests). This is the single highest-leverage change in the repo. Effort: 1-2 hrs, needs your review of what stays always-loaded.

**F7. MANIFEST.md is stale and manually maintained.**
`MANIFEST.md:48` says "(24 files)"; guidance/ has 38. 12+ files missing from the table (deep-research, learning-agent, mcp-tools, prior-work-lookup, public-app-isolation, repo-creation, research-quality, stop-hook-safety, warehouse-analytics, when-to-fan-out, wiki-consultation, comprehensive-closeout).
Fix: generate the guidance table from files via a script and add a drift check to hook-health-check.sh so it never goes stale again. Effort: 45 min.

**F8. Guidance files lack consistent "Load when:" headers.**
Some files state trigger conditions (learning-capture.md); most rely solely on the one-liner in agent.md's index. When an agent opens a file mid-task it cannot cheaply confirm relevance.
Fix: one-line `<!-- Load when: ... -->` header on all 38 files, copied from the agent.md index entry. Mechanical. Effort: 45 min.

**F9. process-hygiene.md is 597 lines mixing universal rules with ~12 narrow incident writeups** (MediaPipe WSL2, Node 22 fetch timeout, cron PATH, Docker gotchas).
Fix: keep ~250 lines of universal rules; move incident patterns to knowledgeBase/patterns/ where the wiki index already points agents. Effort: 1 hr.

**F10. Session-end guidance is split across three overlapping files** (session-wrapup.md 92L, comprehensive-closeout.md 116L, session-lifecycle.md 47L) with unclear boundaries and a contradiction about whether deep closeout is automatic (session-wrapup step 12 requires a manual script call).
Fix: fold comprehensive-closeout into session-wrapup as an "important sessions" section; session-lifecycle keeps only ephemerality/crash-recovery. Resolve the automatic-vs-manual wording against what the Stop hooks actually do. Effort: 1 hr.

**F11. Low-value SessionStart injections.**
The "RECENT WORDPRESS POSTS" block (10 posts, mostly 2024-2025) and the raw "RECENT CLI INTERACTIONS" block (opaque IDs, truncated lines) rarely change behavior. Together they cost several hundred tokens per session.
Fix: drop WP posts from SessionStart (search-wp-posts.sh exists for on-demand lookup); reduce CLI interactions to a count + last-session summary line, or drop. Effort: 20 min.

### P2: repo hygiene and structure

**F12. Tracked churn and personal data in a public repo.**
Tracked and constantly modified: `reports/hook-health-check.log`, `reports/hook-health-cron.log`; modified-but-untracked-state churn: `scripts/security-scanner/codex-state.json`. Tracked personal data: `recurring-tasks/logs/job-search-2026-03-19.log`. (The .env files themselves are correctly untracked; only .env.example is committed.)
Fix: `git rm --cached` the logs + job-search log, extend .gitignore (`reports/*.log`, `scripts/security-scanner/*state.json`, `recurring-tasks/logs/`). Effort: 15 min.

**F13. Operational services living in the guidance repo.**
security-scanner (cron service, 100+ log files, 12MB), daily-tldr (cron + 60 tracked tldr-*.json reports), supervisor/reports (live run artifacts). A behavioral-guidance library should not carry runtime state; it bloats the repo (27MB) and every clone.
Fix (larger, optional): new `agentRuntime` repo (or fold into privateContext if any of it is sensitive); agentGuidance keeps docs pointing at it. Crons need path updates. Effort: 2-3 hrs.

**F14. Orphan hooks.**
`hooks/fetch-rules.sh` and `hooks/claudemd-drift-check.sh` are wired in no settings.json (superseded by inline equivalents); `hooks/search-wp-posts.sh` is a CLI utility, not a hook.
Fix: delete the first two (git history preserves them); move search-wp-posts.sh to scripts/. Effort: 10 min.

**F15. Assorted small fixes.**
- `scripts/hook-health-check.sh:62` defaults WP_SITE to https://example.com, guaranteeing a misleading FAIL; skip when unset.
- `hooks/verify-deploy.sh` single-attempt HTTP checks cause false FAILs on transient blips; add one retry.
- agent.md:1 header date (2026-04-04) vs actual late-June edits; either maintain it or drop the date and trust git.
- README.md profile count (says 15, repo has 17).
- Hooks swallow errors with `2>/dev/null || true`; honor a `HOOK_DEBUG=1` env var that surfaces suppressed errors.
- `~/.claude/agents/*.md` copies are content-identical but stale-dated; add a sync step to propagate-hooks.sh so future edits propagate.

**F16. Profiles: decide their status.**
profiles/ is referenced by nothing in hooks/, scripts/, or .claude/ (only by claude-agents/*.md prose); 10 of 17 experience.md files untouched since 2026-04-06. Either wire them (claude-agents definitions explicitly read their profile + experience at spawn) or mark the directory archival in README. Effort: decision + 30 min.

## What is healthy (no action)

- Stop-hook recursion protection: both Claude-invoking Stop hooks (score-session, trigger-learning-review) use stop-hook-guard with `--invokes-claude`, rate-limited 5/hr. The 199M-token incident class is properly closed.
- Secrets: no credentials, webhook URLs, private IPs, or hostnames found in any tracked guidance/hook file; redaction patterns in post-to-discord.sh and save-to-wp-repo.sh are in place; .env files untracked.
- Graduated-rules system (ESSENTIAL demotion with programmatic enforcement) is working as designed and is a good pattern.
- The guidance index in agent.md is complete and accurate.
