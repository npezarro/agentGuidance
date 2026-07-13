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
39 guidance files. Descriptions come from each file's "Load when:" header.

| File | Load when |
|---|---|
| `guidance/ESSENTIAL.md` | AUTO-LOADED at SessionStart: top most-violated rules |
| `guidance/ab-testing.md` | claude-bakeoff A/B testing |
| `guidance/agent-journal.md` | async cross-session journal system |
| `guidance/auth-basepath.md` | authentication and base path patterns |
| `guidance/auto-posting.md` | writing style, multi-destination design |
| `guidance/browser-page-reader.md` | MISSING Load-when header — add one |
| `guidance/code-review.md` | self-review checklist before committing |
| `guidance/comprehensive-closeout.md` | detailed session documentation for important conversations |
| `guidance/context-progress.md` | context.md and progress.md specs |
| `guidance/debugging.md` | diagnosing issues, log analysis |
| `guidance/deep-research.md` | research depth and methodology before producing guides or recommendations |
| `guidance/dependencies.md` | evaluating and adding packages |
| `guidance/deployment.md` | pre-deploy and post-deploy checklists |
| `guidance/discord-integration.md` | session reporting, posting, threading, file-links |
| `guidance/git-workflow.md` | branching, PRs, merge procedures, commit messages |
| `guidance/learning-agent.md` | hourly learning review: passes, staging, PR workflow |
| `guidance/learning-capture.md` | when and where to persist operational learnings |
| `guidance/local-worker-bridge.md` | local worker bridge post-mortem |
| `guidance/mcp-tools.md` | MCP tool provider selection (Claude AI vs piotr google-drive) |
| `guidance/multi-session.md` | continuity checklist and `--refresh` command |
| `guidance/operational-safety.md` | self-deploy loops, restart storms, hook loops |
| `guidance/prior-work-lookup.md` | finding past conversations and prior work |
| `guidance/process-hygiene.md` | spawned processes, temp files, port conflicts |
| `guidance/public-app-isolation.md` | siloed alt account pattern for public-facing apps with untrusted input |
| `guidance/repo-creation.md` | checklist for new repos: cross-cutting guidance incorporation, CLAUDE.md structure |
| `guidance/research-quality.md` | curating high-quality references and study resources |
| `guidance/resource-awareness.md` | server resource checks |
| `guidance/secrets-hygiene.md` | secret rotation, history rewrite, detection patterns |
| `guidance/session-lifecycle.md` | ephemerality, output design, crash recovery |
| `guidance/session-wrapup.md` | end-of-session 7-step checklist |
| `guidance/stop-hook-safety.md` | tiered stop hook classification, guard library, Tier 3 recursion prevention |
| `guidance/synthetic-panel.md` | proposing, building, or shipping a user-facing product change; want structured synthetic-user feedback on an idea |
| `guidance/tampermonkey.md` | TM script hosting and CAPTCHA bypass patterns |
| `guidance/testing.md` | writing and running tests, cross-layer invariants |
| `guidance/warehouse-analytics.md` | Snowflake/warehouse pull → DuckDB analysis → publish; auth ladder + cost gate + publish gotchas |
| `guidance/when-to-fan-out.md` | when to spawn subagents (Task fan-out / parallel bash / Workflow) vs stay single-agent; concurrency-safe 3-phase pattern |
| `guidance/wiki-consultation.md` | when and how to consult knowledgeBase wiki pages |
| `guidance/wordpress-auto-posting.md` | WordPress hook setup |
| `guidance/written-voice.md` | writing in the owner's voice |
<!-- END GENERATED -->

## Rules vs Guidance

- **`~/repos/privateContext/rules/`** (2 files): Environment-specific constraints installed to `~/.claude/rules/` via `scripts/install-rules.sh`. VM deploy safety and usage guardrails. Kept in privateContext because they contain infrastructure details.
- **`guidance/`**: Detailed procedures loaded on-demand (count and list in the generated table above). `ESSENTIAL.md` is auto-loaded; rest are on-demand. One file per function; no duplication.
- **`scripts/`**: Operational scripts (`propagate-learning.sh`, etc.)
- **`agent.md`**: Slim routing table (~80 lines) with core principles and the guidance index.

## Adding New Functions

1. Create a new `guidance/<function>.md` file
2. Run `scripts/gen-manifest.sh` (the guidance table is generated from each file's Load-when header)
3. Add a pointer in agent.md's Guidance File Index
4. Do NOT duplicate the content in `~/.claude/rules/` unless it's VM/environment-specific
