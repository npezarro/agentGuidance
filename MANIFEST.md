# Manifest: Function to Canonical Source

Every operational function has exactly one canonical source. If you need to find or update a rule, this is where it lives.

| Function | Canonical Source | Notes |
|---|---|---|
| Identity and stack defaults | `agent.md` | Always loaded at session start |
| Core behavioral principles | `agent.md` | Plan, validate, push, ask |
| Credential lookup | `~/repos/privateContext/` | Search before asking user |
| Deployment (VM safety) | `~/repos/privateContext/rules/deploy-safety.md` | VM-specific: disk, large-file-storage, branches |
| Usage guardrail | `~/repos/privateContext/rules/usage-guardrail.md` | Team spawn gate at 75% |
| Learning propagation script | `scripts/propagate-learning.sh` | Single-command multi-destination learning routing |
| Cross-repo knowledge wiki | `~/repos/knowledgeBase/` | Synthesized cross-cutting reference; MANIFEST.md maps pages to sources |

## Guidance Files (generated)

<!-- BEGIN GENERATED guidance table (scripts/gen-manifest.sh) -->
45 guidance files (36 indexed at SessionStart via `guidance/INDEX.md`, 9 cold). Descriptions come from each file's "Load when:" header.

| File | Load when |
|---|---|
| `guidance/ESSENTIAL.md` | AUTO-LOADED at SessionStart: top most-violated rules |
| `guidance/ab-testing.md` | claude-bakeoff A/B testing _(cold: not indexed at SessionStart)_ |
| `guidance/agent-journal.md` | async cross-session journal system |
| `guidance/auth-basepath.md` | authentication and base path patterns |
| `guidance/auto-posting.md` | writing style, multi-destination design |
| `guidance/browser-page-reader.md` | page-reader CLI for JS-heavy pages |
| `guidance/code-review.md` | self-review checklist before committing |
| `guidance/comprehensive-closeout.md` | detailed session documentation for important conversations _(cold: not indexed at SessionStart)_ |
| `guidance/concurrent-sessions.md` | several sessions share one checkout; worktrees, resource locks, claim-guard, "it keeps reverting" |
| `guidance/context-progress.md` | context.md and progress.md specs _(cold: not indexed at SessionStart)_ |
| `guidance/debugging.md` | diagnosing issues, log analysis |
| `guidance/deep-research.md` | research depth and methodology before producing guides or recommendations |
| `guidance/dependencies.md` | evaluating and adding packages _(cold: not indexed at SessionStart)_ |
| `guidance/deployment.md` | pre-deploy and post-deploy checklists |
| `guidance/discord-integration.md` | session reporting, posting, threading, file-links |
| `guidance/fact-checking.md` | mandatory search-verification of external actionable claims (prices, eligibility rules, offers) before asserting |
| `guidance/git-workflow.md` | branching, PRs, merge procedures, commit messages |
| `guidance/goal-conditions.md` | /goal for headless runners: mission-file pattern, condition rules, BLOCKED escape hatch |
| `guidance/learning-agent.md` | hourly learning review: passes, staging, PR workflow |
| `guidance/learning-capture.md` | when and where to persist operational learnings |
| `guidance/literature-search.md` | a claim is scientific/medical/technical and primary literature would settle it better than web search |
| `guidance/local-worker-bridge.md` | local worker bridge post-mortem |
| `guidance/mcp-tools.md` | MCP tool provider selection (Claude AI vs piotr google-drive) |
| `guidance/multi-session.md` | continuity checklist and `--refresh` command _(cold: not indexed at SessionStart)_ |
| `guidance/operational-safety.md` | self-deploy loops, restart storms, hook loops |
| `guidance/opus-fable-parity.md` | validated instruction layer closing the Opus 4.8 -> Fable 5 behavioral gap; inject into Opus pipelines needing Fable-grade rigor (requires >=45-turn budget) |
| `guidance/prior-work-lookup.md` | finding past conversations and prior work |
| `guidance/process-hygiene.md` | spawned processes, temp files, port conflicts |
| `guidance/provenance.md` | producing any deliverable that contains researched/generated facts; capturing sources |
| `guidance/public-app-isolation.md` | siloed alt account pattern for public-facing apps with untrusted input |
| `guidance/repo-creation.md` | checklist for new repos: cross-cutting guidance incorporation, CLAUDE.md structure |
| `guidance/research-quality.md` | curating high-quality references and study resources _(cold: not indexed at SessionStart)_ |
| `guidance/resource-awareness.md` | server resource checks |
| `guidance/secrets-hygiene.md` | secret rotation, history rewrite, detection patterns |
| `guidance/session-lifecycle.md` | ephemerality, output design, crash recovery _(cold: not indexed at SessionStart)_ |
| `guidance/session-wrapup.md` | end-of-session 7-step checklist _(cold: not indexed at SessionStart)_ |
| `guidance/stop-hook-safety.md` | tiered stop hook classification, guard library, Tier 3 recursion prevention |
| `guidance/synthetic-panel.md` | proposing, building, or shipping a user-facing product change; want structured synthetic-user feedback on an idea |
| `guidance/tampermonkey.md` | TM script hosting and CAPTCHA bypass patterns |
| `guidance/testing.md` | writing and running tests, cross-layer invariants |
| `guidance/warehouse-analytics.md` | Snowflake/warehouse pull → DuckDB analysis → publish; auth ladder + cost gate + publish gotchas |
| `guidance/when-to-fan-out.md` | when to spawn subagents (Task fan-out / parallel bash / Workflow) vs stay single-agent; concurrency-safe 3-phase pattern |
| `guidance/wiki-consultation.md` | when and how to consult knowledgeBase wiki pages _(cold: not indexed at SessionStart)_ |
| `guidance/wordpress-auto-posting.md` | WordPress hook setup |
| `guidance/written-voice.md` | writing in the owner's voice |
<!-- END GENERATED -->

## Rules vs Guidance

- **`~/repos/privateContext/rules/`** (2 files): Environment-specific constraints installed to `~/.claude/rules/` via `scripts/install-rules.sh`. VM deploy safety and usage guardrails. Kept in privateContext because they contain infrastructure details.
- **`guidance/`**: Detailed procedures loaded on-demand (count and list in the generated table above). `ESSENTIAL.md` is auto-loaded; rest are on-demand. One file per function; no duplication.
- **`scripts/`**: Operational scripts (`propagate-learning.sh`, etc.)
- **`agent.md`**: Slim behavioral rules (~45 lines). Core principles only; the guidance index moved to `guidance/INDEX.md` (generated) so agent.md stops growing with every new guidance file.
- **`guidance/INDEX.md`**: Generated hot-subset index, injected at SessionStart alongside `agent.md` and `ESSENTIAL.md`. Do not hand-edit; run `scripts/gen-manifest.sh`.

## Adding New Functions

1. Create a new `guidance/<function>.md` file, with a `<!-- Load when: ... -->` header in its first 5 lines
2. Run `scripts/gen-manifest.sh` and commit both regenerated artifacts: the table above and `guidance/INDEX.md`
3. Nothing to add in `agent.md` — it no longer carries the index, so new guidance files cost it zero lines
4. Do NOT duplicate the content in `~/.claude/rules/` unless it's VM/environment-specific

To retire a guidance file without deleting it, add it to the `COLD` set in `scripts/gen-manifest.sh`: it drops out of `guidance/INDEX.md` (so it stops consuming SessionStart context) but stays on disk and stays listed above. Delete the line to re-promote it.
