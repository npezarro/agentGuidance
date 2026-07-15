<!-- Load when: hourly learning review: passes, staging, PR workflow -->
# Learning Agent — Design

A dedicated agent that periodically reviews recent work across all repos, identifies patterns and learnings that weren't captured, and persists them to the right instruction files.

## Problem Statement

Learnings get lost because:
1. Session agents are focused on the task at hand and forget to persist
2. Even with the multi-destination rule, enforcement is behavioral (no automated check)
3. Cross-repo patterns only emerge when reviewing multiple repos together
4. Prompt and instruction drift happens gradually and goes unnoticed

## Architecture

### Runner
- Location: `~/repos/autonomousDev/learnings-pass/`
- Invoked by: Cron (every 4 hours at :43)
- Runtime: Claude CLI with a focused prompt
- Timeout: 30 minutes (`MAX_TIMEOUT=1800` in run.sh)

### Capacity Gate
- **Skip if:** 5-day or 7-day usage >= 90% (this is a high-priority but not critical job)
- Uses `~/repos/privateContext/check-usage.sh --gate-90` (needs a threshold flag added)
- Also skips if auto-dev or fix-checker is currently running (check PM2 / pidfile)

### What It Reviews (Input)

Each run reviews a sliding window of recent activity:

1. **Git logs across all repos** (last 24h of commits)
   - `git log --since="24 hours ago" --oneline` across whitelisted repos
   - Identifies what was worked on, by whom (human vs agent)

2. **Agent journal entries** (last 24h)
   - Recent discoveries, observations, suggestions from `#agent-journal`

3. **Discord #cli-interactions** (last 24h)
   - Session reports, especially follow-ups and open items

4. **Memory files** (all)
   - Check for learnings saved to memory but NOT to agentGuidance/privateContext
   - This is the "enforcement" layer for the multi-destination rule

5. **Existing guidance files** (agentGuidance/guidance/)
   - Check for staleness, contradictions, gaps

### What It Produces (Output)

1. **Guidance updates** — Edits to existing `agentGuidance/guidance/*.md` files or new files when a gap is identified
2. ~~Profile experience entries~~ — retired 2026-07-01 (profiles/ removed from agentGuidance)
3. **Prompt refinements** — Updates to `privateContext/prompts/*.md` when a prompt strategy worked well or failed
4. **CLAUDE.md patches** — Updates to specific repo CLAUDE.md files when repo-specific learnings weren't captured
5. **Journal entries** — Posts observations to agent-journal for other sessions to see
6. **Discord report** — Summary of what was reviewed and what was captured, posted to a dedicated channel (e.g., `#learnings` or `#agent-journal`)

### What It Does NOT Do

- Write code or make functional changes to repos
- Run builds or tests
- Deploy anything
- Commit directly to main (all changes go on branches with PRs for review)
- Duplicate information that's already captured

## Review Process

The agent follows a structured review loop:

```
1. SCAN — Gather recent activity (git logs, journal, memory)
2. DIFF — Compare against existing guidance (what's new vs what's already documented)
3. CLASSIFY — For each undocumented learning:
   - Is it repo-specific or cross-project?
   - Is it sensitive (→ privateContext) or safe (→ agentGuidance)?
   - Is it a new pattern or an update to an existing rule?
4. PERSIST — Write to the right destination(s)
5. VERIFY — Confirm changes don't violate secrets-hygiene rules
6. REPORT — Post a summary of what was captured
```

## Prompt Design

The learning agent needs a focused prompt that:
- Lists all repos to scan (from auto-dev config.json)
- Explains the multi-destination rule (memory, repo CLAUDE.md, agentGuidance/privateContext, knowledgeBase) and the agentGuidance vs privateContext boundary
- Provides the secrets-hygiene checklist for pre-commit review
- Instructs it to be conservative (only capture genuine patterns, not noise)
- Tells it to UPDATE existing guidance files rather than create new ones when possible

## Safeguards

1. **No sensitive info in agentGuidance** — Pre-commit grep for IPs, hostnames, usernames, private repo names (from sensitive-identifiers.md)
2. **Conservative capture** — Only persist learnings that appear across 2+ sessions or that a user explicitly called out
3. **Append-only for experience logs** — Never edit or delete existing profile experience entries
4. **Diff review** — Before committing, show the full diff and validate against secrets-hygiene
5. **Idempotent** — Running twice on the same data should produce no additional changes
6. **Dedup against the active consolidation branch, not just `main`** — When the open-PR cap is reached, prior runs commit new content onto the newest existing open learnings branch (e.g. `claude/learnings-775`) instead of merging it to `main`. That branch can sit open for many runs. A dedup check that only greps `main` will re-"discover" gaps that a recent run already staged on the open branch (confirmed run #872: 3 of 4 candidate findings were already present on `claude/learnings-775` despite being absent from `main`). Before treating something as a gap, check both `main` AND the current open consolidation branch's content (`git show <branch>:<file>` or check out the branch in a worktree) — never just `main`.
7. **A staged fix is not live until it's merged — verify, don't infer, before calling it "shipped."** `claude/learnings-*` branches are on the auto-merger's denylist by design (`knowledgeBase/agent-system/auto-merger.md`) — they never self-merge, unlike `claude/auto-*`/`gemini/fix-*` branches. Run #907 shipped S217 (a `wsl-watchdog.sh` stranded-checkout auto-heal) as PR `scripts#58` and marked it "resolved"; runs #908-#911 then repeated "live since run #907" / "appears to be holding" in their journal entries and `completed-work.md` without ever running `gh pr view 58 --json state`. The PR was still `OPEN`, `CLEAN`/`MERGEABLE`, unreviewed — the fix had never executed once (confirmed run #912: `botlink`'s main checkout was independently found stranded on a squash-merged branch, unhealed, because the code protecting against it was never live). Before writing "live"/"shipped"/"holding"/"in production" about any change from a prior run, run `gh pr view <n> --json state,mergedAt` (or equivalent for non-PR changes) and cite the actual state. If a PR is still open, say "staged, awaiting merge" — not "live."

## Integration with Existing Systems

| System | How Learning Agent Interacts |
|---|---|
| auto-dev | Reads its progress logs; doesn't compete for resources |
| fix-checker | Reads its failure logs for patterns |
| agent-journal | Reads recent entries; posts its own findings |
| session-wrapup | Catches what session wrapup missed |
| memory system | Audits for memory-only learnings |
| MANIFEST.md | Consults for canonical source locations |

## Decisions (finalized 2026-04-05)

1. **Frequency:** Every 4 hours (cron at :43). Skips when 5d or 7d usage >= 90%. Reduced from hourly on 2026-05-08 to conserve token budget.
2. **Discord channel:** `#learnings` (dedicated channel, `DISCORD_LEARNINGS_WEBHOOK_URL` env var).
3. **Approval flow:** Staged — all changes on branches with PRs. User reviews and merges. No direct commits to main.
4. **Scope:** Observes and suggests on everything — auto-dev, fix-checker, all repo CLAUDE.md files, agentGuidance itself.
5. **Correction detection:** Scans for user corrections in Discord #cli-interactions and git history that aren't reflected in any rule set. Highest priority capture target.

## Implementation

- **Location:** `~/repos/autonomousDev/learnings-pass/`
- **Runner:** `run.sh` (hourly cron)
- **Prompt:** `prompt.md` (7-pass review: uncaptured learnings, memory audit, correction detection, prompt observation, profile updates, ESSENTIAL.md check, wiki cross-reference)
- **Suggestions log:** `suggestions.md` (append-only, for prompt/instruction improvement ideas)
