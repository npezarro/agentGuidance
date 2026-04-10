# Manifest: Function to Canonical Source

Every operational function has exactly one canonical source. If you need to find or update a rule, this is where it lives.

| Function | Canonical Source | Notes |
|---|---|---|
| Identity and stack defaults | `agent.md` | Always loaded at session start |
| Core behavioral principles | `agent.md` | Plan, validate, push, ask |
| Credential lookup | `~/repos/privateContext/` | Search before asking user |
| Session reporting (Discord) | `guidance/discord-integration.md` | Webhooks, threading, file-links |
| Session wrap-up | `guidance/session-wrapup.md` | 7-step end-of-session checklist |
| Session continuity | `guidance/multi-session.md` | Picking up previous work |
| Session lifecycle | `guidance/session-lifecycle.md` | Ephemerality, crash recovery |
| Agent journal | `guidance/agent-journal.md` | Cross-session async notes |
| Git workflow | `guidance/git-workflow.md` | Branching, PRs, merges, commit messages |
| Code review | `guidance/code-review.md` | Pre-commit self-review checklist |
| Context and progress files | `guidance/context-progress.md` | context.md and progress.md specs |
| Testing | `guidance/testing.md` | Writing, running, cross-layer invariants |
| Debugging | `guidance/debugging.md` | Log analysis, reproduce, isolate |
| Deployment (general) | `guidance/deployment.md` | Pre-deploy and post-deploy checklists |
| Deployment (VM safety) | `~/.claude/rules/deploy-safety.md` | VM-specific: disk, large-file-storage, branches |
| Dependencies | `guidance/dependencies.md` | Evaluating and adding packages |
| Resource awareness | `guidance/resource-awareness.md` | Server resource checks |
| Process hygiene | `guidance/process-hygiene.md` | Spawned processes, temp files, ports |
| Operational safety | `guidance/operational-safety.md` | Self-deploy loops, restart storms |
| Secrets hygiene | `guidance/secrets-hygiene.md` | Rotation, history rewrite, detection |
| Usage guardrail | `~/.claude/rules/usage-guardrail.md` | Team spawn gate at 75% |
| Agent profiles | `profiles/_schema.md` | Identity + experience log format |
| Written voice | `guidance/written-voice.md` | Writing in the owner's voice |
| WordPress posting | `guidance/wordpress-auto-posting.md` | WordPress hook setup |
| Auto-posting | `guidance/auto-posting.md` | Multi-destination posting design |
| A/B testing | `guidance/ab-testing.md` | claude-bakeoff framework |
| Auth and base paths | `guidance/auth-basepath.md` | Authentication patterns |
| Browser page reader | `guidance/browser-page-reader.md` | page-reader CLI for JS pages |
| Local worker bridge | `guidance/local-worker-bridge.md` | Post-mortem reference |
| Tampermonkey | `guidance/tampermonkey.md` | Script hosting, CAPTCHA patterns |
| Learning capture | `guidance/learning-capture.md` | When/where to persist learnings (multi-destination rule) |
| Comprehensive closeout | `guidance/comprehensive-closeout.md` | Detailed session documentation for important conversations |
| Cross-repo knowledge wiki | `~/repos/knowledgeBase/` | Synthesized cross-cutting reference; MANIFEST.md maps pages to sources |

## Rules vs Guidance

- **`~/.claude/rules/`** (2 files): Environment-specific constraints that are always loaded. VM deploy safety and usage guardrails.
- **`guidance/`** (23 files): Detailed procedures loaded on-demand. One file per function; no duplication.
- **`agent.md`**: Slim routing table (~75 lines) with core principles and the guidance index.
- **`profiles/`**: Agent identity and experience. One subdirectory per agent.

## Adding New Functions

1. Create a new `guidance/<function>.md` file
2. Add a row to this manifest
3. Add a pointer in agent.md's Guidance File Index
4. Do NOT duplicate the content in `~/.claude/rules/` unless it's VM/environment-specific
