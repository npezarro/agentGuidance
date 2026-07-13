# Progress Log

> Continuously updated log of all work done on this project. Add entries in reverse chronological order (newest first). One entry per PR, deploy, or significant change. Keep entries concise — 1-2 lines max.
>
> **Update rules:**
> - Add an entry for every merged PR or significant commit
> - Add an entry for every deploy
> - Log infrastructure changes (env vars, server config, deps)
> - Never include secrets, credentials, or .env contents
> - Format: `YYYY-MM-DD | <type> | <description>`

## Log
2026-07-12 | guidance | testing.md: "Fallback Chains Hide Dead Rungs" rule (PR #318) — test each fallback branch in isolation; ship a canary asserting the winning rung; verify the real code path not a reimplementation. From the fetch-page.sh silent-miss (rung 1 dead, rung 2 masked it).
2026-07-12 | incident | Quarantined an unpushed concurrent-automation commit (f68e8c5) that added sensitive identifiers (VM SSH username + a Discord-bot module path) to guidance/opus-fable-parity.md in this PUBLIC repo. Local-only, never pushed; held in git stash@{0} pending sanitization. See closeout.
2026-07-12 | feature | Provenance + source-capture system (PR #314): guidance/provenance.md, scripts/source-registry.sh, agent.md + ESSENTIAL.md wiring. Companion private repo sourceLibrary created. Marks Claude-generated facts vs Nick's writing; captures cited sources with cached material.

- 2026-07-09 | guidance | `c1ef193` — ESSENTIAL rule 5 new bullet "Intended state before config changes": read a project's docs before altering config/lifecycle (restart policy, enable/disable). From the 2026-07-09 power-cut recovery where `humans-pg` (documented on-demand dev DB, `restart:no` by design) was made `unless-stopped` on a hunch.
- 2026-07-04 | guidance | `8e41e02` — ESSENTIAL rule 3 externally-verifiable-facts clause + `guidance/fact-checking.md` + agent.md index line; companion `/fact-check` skill in claude-skills. From the 2026-07-03 CC-thread postmortem.

| 2026-06-30 | fix | `9c81340` bound the always-loaded MEMORY.md index to its ~24.4KB budget: `propagate-learning.sh` caps the index hook to ~128 chars on append (flock-coordinated); new `hooks/compact-memory-index.sh` SessionStart self-heal (non-destructive, idempotent, warns/`--check` over hard limit); `guidance/learning-capture.md` "MEMORY.md Index Budget" section. Root cause: unbounded SUMMARY append. Index 32KB→~22.5KB, 12 redundant/superseded memories archived. |
| 2026-06-30 | fix | `25be864` made `compact-memory-index.sh` machine-agnostic: hook mode heals the current project's index (CLAUDE_PROJECT_DIR/PWD slug, fallback to interactive primary); `--check` audits all indexes. Required because the VM's home-dir project slug (non-`npezarro`) wasn't matched by the original hardcoded globs. Wired+verified on this host + VM; pc2 pending (WSL sshd down). Surfaced a 626KB malformed autonomousDev-private index (warns, can't auto-fix). |
| 2026-06-30 | docs | knowledgeBase `agent-system/memory-system.md` + `infra/{windows-pc,macbook}-claude-code.md`: new machines wire `compact-memory-index.sh` into global SessionStart (curl-from-main pattern); per-machine wiring caveat documented. |
| 2026-06-29 | docs | `a34adbb` wired the page-access waterfall into `guidance/browser-page-reader.md` (WebFetch → page-reader → feed/transcript tricks → authenticated browser-agent → WebSearch + sub-agent rule) and `guidance/deep-research.md` (2 anti-patterns: don't surrender at first block; don't let WebFetch-only sub-agents launder search summaries). Companion `page-access` skill in claude-skills. |
| 2026-06-23 | feat | `dbeea10` post-to-discord hook: extract `message.model` from transcript → `/ingest` payload metadata, so #cli-interactions becomes a model-tagged outcome feed (enables forward model A/B). Pairs with a Discord bot renderer change. |

| Date | Type | Description |
|------|------|-------------|
| 2026-06-10 | feat | Section 7 implementation (this repo's share): check-repo-writer.sh PostToolUse hook (writer/canonical-copy declarations; split-brain caught at edit time), load-repo-context.sh SessionStart hook (per-repo context packs), ESSENTIAL.md 16→10 with graduation policy, agent-journal signal-gate rules, code-review.md gains the graduated CLAUDE.md-update rule. settings.json hooks all local now (raw-URL fetches retired). Closeout: privateContext/deliverables/closeouts/2026-06-10-section7-implementation.md |
| 2026-06-09 | fix | trigger-learning-review.sh: add `--invokes-claude` to stop_hook_init. The hook spawned learnings-pass (a full claude -p run) without the env circuit breaker or 5/hr cap, so learning runs re-triggered themselves: 7-20 runs/day observed vs 3 scheduled. Found by the Fable 5 ecosystem review (two independent reviewers); paired with a guard export in the private runner. Report: privateContext/deliverables/audits/2026-06-09-fable5-ecosystem-review.md |
| 2026-06-08 | docs | Cover Letter Header rule in `guidance/written-voice.md`: pointer-only entry to `privateContext/guidance/cover-letter-header.md` (literal values held private). Enforced via `write-as-nick` skill Quality Gate. Pre-commit sensitive-identifier hook correctly blocked the naive single-file edit and forced the public/private split. Commit 5296640 on `claude/learnings-685`. |
| 2026-06-03 | docs | ESSENTIAL rule 16: suggest `/onboard` for compound-task signals (3+ files, multiple verbs, unfamiliar repos, multi-phase); skip for single-file edits, known-cause fixes, lookups, tasks inside documented projects. Pairs with `onboard` skill in claude-skills. Commit dd8d6f9. |
| 2026-06-02 | docs | README polish: lead with Claude Code harness framing, add Operating in Production metrics, expand Related Projects → 9-entry Ecosystem section, fix broken auto-dev link. Threshold redaction (50%/75% → "configurable") in claude-usage-monitor description. Metrics refresh: ~24K LOC, 175+ autonomous commits, 655+ learning-agent runs, 45+ wiki pages. Commits 8829fc5, fc60a65, 70997f3. |
| 2026-05-26 | docs | Add "LinkedIn posts: milestone / story-time" register to guidance/written-voice.md synopsis (longer story posts, full-name collaborator credits, celebrate others, no private repo names) |
| 2026-04-23 | feat | Add git-push-reminder.sh PostToolUse hook: fires on Edit/Write, reminds agent to commit+push when file has uncommitted changes in a git repo. Added to ~/.claude/settings.json |
| 2026-04-19 | feat | Broaden auto-file-links.sh to post links for all .md files on push (was limited to output/report dirs) |
| 2026-03-20 | docs | Overhaul guidance/testing.md with testing pyramid strategy (failure audit, contract tests, integration tests, smoke tests, browser tests); add templates/failure-audit.md |
| 2026-03-20 | feat | Parameterize send-email.js sender name (arg or SENDER_NAME env var), fix .env load order so ALERT_EMAIL resolves in cron context |
| 2026-03-19 | feat | Add recurring-tasks infrastructure: shared runner.sh with flock locking, scoped permissions, Discord notifications; crontab generator |
| 2026-03-18 | fix | Add retry logic for PR creation in agent.md: wait for branch registration, retry gh pr create 3x, never fall back to manual URLs |
| 2026-03-17 | feat | Add shared ESLint 9 flat config (eslint/) with base JS rules and optional TypeScript overrides for cross-repo use |
| 2026-03-17 | docs | Confirmed promptlibrary PR #5 already closed (2026-03-15) due to stale conflicts; updated context.md to reflect resolved status |
| 2026-03-14 | infra | Propagated `.gitattributes` with `merge=union` to all 15 repos on main; rebased and merged 19 of 20 conflicting PRs across 7 repos |
| 2026-03-14 | docs | Add Branch Hygiene section to Git Workflow: merge PRs promptly, rebase before opening PRs, clean up stale branches |
| 2026-03-14 | fix | Prevent merge conflicts: add `.gitattributes` with `merge=union` for progress.md, reduce context.md update frequency to final-branch-commit only, add `.gitattributes` to self-review checklist, update propagation script |
| 2026-03-14 | docs | Remove all em dashes from agent.md, add no-em-dash writing convention to Communication section |
| 2026-03-10 | feat | Add real-world examples to templates/context.md and templates/progress.md, 3 project-type examples each (bot, web app, CLI tool), all sanitized |
| 2026-03-07 | feat | Add three guidance files (session-lifecycle, resource-awareness, process-hygiene) distilled from Discord bot development; expand agent.md with post-deploy verification, logs-first debugging, and multi-destination output design |
| 2026-03-07 | docs | Elevate progress.md to mandatory core instruction — every commit requires an entry; remove "Recent Changes" from context.md spec to eliminate dual-source drift |
| 2026-03-07 | refactor | Extract Discord details from agent.md to discord-bot repo, add progress.md system |
| 2026-03-05 | PR #11 | Agent/Public Repo Warning — duplicate PR merged |
| 2026-03-04 | PR #10 | Add public repo warning and expand Security section |
| 2026-03-04 | PR #7 | Expand Discord Integration for full agent-server interaction |
| 2026-03-04 | PR #6 | Agent/Expand Discord Integration |
| 2026-03-04 | PR #5 | Add Discord Integration section to global agent rules |
| 2026-03-04 | PR #3 | Add Discord stop hook for agent turn logging |
| 2026-03-04 | PR #2 | Add Regression & Functional Verification to Testing rules |
| 2026-03-01 | PR #1 | Comprehensive guidance improvements with modular sub-guidance and templates |

## 2026-07-01 — Full-repo review implementation
- `b83772a` review report (16 findings); `32e6c3b` agent.md v4.1.0 ESSENTIAL dedup; `c5bc0c6` hygiene (untrack logs/personal data, orphan hooks); `674a176` profiles/ removed; `da658ca` services extracted to private agentRuntime; `3793370` hooks bug batch; `5e1bbe9` portability (grep -P/flock); `2c093fc` guidance consolidation (Load-when headers, session-end dedup, process-hygiene split); `b505d00` generated MANIFEST + drift check.
- Cross-repo: knowledgeBase `patterns/runtime-gotchas.md`; autonomousDev-private `e82f05f` (learning-agent Pass 5 retired); new repo github.com/npezarro/agentRuntime; crontab updated; VM clone re-created (was divergent+stale), pc2 synced.
- check-commit-deploy gate: honor /tmp/claude-deploy-ack-<sid> for docs-only commits and subagent-performed deploys (which run under a different session_id and never register in track-deploy); dropped the undetectable "note in context.md" escape from the block message. Both branches tested.
- Stop-hook state lifecycle fix: verify-deploy.sh consumed AND deleted /tmp/claude-deploys-<sid>, so check-commit-deploy re-blocked on every Stop after the first. Tracker now archived to -verified on consumption; the gate reads live + verified + ack files. Regression-tested across two simulated Stops.

## 2026-07-10 — Interactive Opus→Fable parity rollout (WSL) with 85/15 holdout A/B
- `6af79d0` new SessionStart hook `hooks/parity-layer-injection.sh` + `guidance/opus-fable-parity.md` "Interactive-session rollout" section. Injects the parity layer into interactive Opus WSL sessions only; guards skip headless (`/proc/$PPID/cmdline` has `-p`/`--print`) and non-Opus, fail closed. Deterministic 85/15 arm (`cksum(session_id)%100<85`), both arms logged to `~/.claude/parity-telemetry/interactive-arms.jsonl`. Wired as `~/.claude/settings.json` SessionStart entry #9 (local, not in repo).
- Empirical: SessionStart hooks DO fire on local `claude -p` runs (verified via security-scan log), hence the headless guard. Public-repo security scan #70 clean (0/30). Closeout: privateContext/deliverables/closeouts/2026-07-10-interactive-parity-rollout-and-security-review.md

## 2026-07-02 — Skill routing rule from library audit
- `guidance/deployment.md`: new "Skill Routing" section (staging apps list, generic deploy path, fix-static-asset-drift for styling-broken symptoms, vm-health/vm-cleanup). Audit context: 97 zero-skill ssh+pm2 sessions found in 21 days of transcripts. Companion edits in `~/.claude/rules/deploy-safety.md` (not this repo). Closeout: privateContext/deliverables/closeouts/2026-07-02-skill-library-audit-rework.md
