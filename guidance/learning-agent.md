# Learning Agent — Design

A dedicated agent that periodically reviews recent work across all repos, identifies patterns and learnings that weren't captured, and persists them to the right instruction files.

## Problem Statement

Learnings get lost because:
1. Session agents are focused on the task at hand and forget to persist
2. Even with the 3-destination rule, enforcement is behavioral (no automated check)
3. Cross-repo patterns only emerge when reviewing multiple repos together
4. Prompt and instruction drift happens gradually and goes unnoticed

## Architecture

### Runner
- Location: `~/repos/auto-dev/learning-agent/`
- Invoked by: Cron (every 2-4 hours during active development periods)
- Runtime: Claude CLI with a focused prompt
- Timeout: 20 minutes (it's reading and writing, not building)

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
   - This is the "enforcement" layer for the 3-destination rule

5. **Existing guidance files** (agentGuidance/guidance/)
   - Check for staleness, contradictions, gaps

### What It Produces (Output)

1. **Guidance updates** — Edits to existing `agentGuidance/guidance/*.md` files or new files when a gap is identified
2. **Profile experience entries** — Appends to `profiles/<agent>/experience.md` when a session demonstrated a pattern relevant to that profile
3. **Prompt refinements** — Updates to `privateContext/prompts/*.md` when a prompt strategy worked well or failed
4. **CLAUDE.md patches** — Updates to specific repo CLAUDE.md files when repo-specific learnings weren't captured
5. **Journal entries** — Posts observations to agent-journal for other sessions to see
6. **Discord report** — Summary of what was reviewed and what was captured, posted to a dedicated channel (e.g., `#learnings` or `#agent-journal`)

### What It Does NOT Do

- Write code or make functional changes to repos
- Run builds or tests
- Deploy anything
- Create PRs or branches (it edits guidance files on main/production directly)
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
- Explains the 3-destination rule and the agentGuidance vs privateContext boundary
- Provides the secrets-hygiene checklist for pre-commit review
- Instructs it to be conservative (only capture genuine patterns, not noise)
- Tells it to UPDATE existing guidance files rather than create new ones when possible

## Safeguards

1. **No sensitive info in agentGuidance** — Pre-commit grep for IPs, hostnames, usernames, private repo names (from sensitive-identifiers.md)
2. **Conservative capture** — Only persist learnings that appear across 2+ sessions or that a user explicitly called out
3. **Append-only for experience logs** — Never edit or delete existing profile experience entries
4. **Diff review** — Before committing, show the full diff and validate against secrets-hygiene
5. **Idempotent** — Running twice on the same data should produce no additional changes

## Integration with Existing Systems

| System | How Learning Agent Interacts |
|---|---|
| auto-dev | Reads its progress logs; doesn't compete for resources |
| fix-checker | Reads its failure logs for patterns |
| agent-journal | Reads recent entries; posts its own findings |
| session-wrapup | Catches what session wrapup missed |
| memory system | Audits for memory-only learnings |
| MANIFEST.md | Consults for canonical source locations |

## Open Questions

1. **Frequency:** Every 2 hours? Every 4? Once daily? More frequent = more current, but more usage cost. Recommendation: every 4 hours during active periods, skip when idle (no recent commits).
2. **Discord channel:** Use `#agent-journal` or create a dedicated `#learnings` channel?
3. **Approval flow:** Should it auto-commit guidance changes, or create a review queue? Auto-commit is faster but riskier. Recommendation: auto-commit with a mandatory post to Discord showing the diff.
4. **Scope expansion:** Should it also review and suggest prompt improvements for auto-dev and fix-checker prompts?
