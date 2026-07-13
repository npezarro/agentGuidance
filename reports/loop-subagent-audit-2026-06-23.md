# Loop and Subagent Audit (2026-06-23)

Deep audit of the autonomous-agent ecosystem: how recurring "loops" are built, whether they use subagents or parallelism, and where the newer primitives (in-session Task fan-out, parallel bash, the Workflow tool) add value. Commissioned to answer "anything new I should be doing with loops, or more subagents?"

## TL;DR

The scheduling layer is mature; the execution layer is almost entirely single-agent and serial. Two structural gaps:

1. **No independent verification in the loop that self-merges.** fix-checker squash-merges to main with no deterministic gate and a documented history of asserting fixes without evidence. This is the highest-value gap.
2. **N-independent-item loops run strictly serially.** The gemini-PR reviewer, job-pipeline, and auto-shorts learning each call Claude once per item in a serial loop. Pure wall-clock waste.

The subagent library (7 agent defs, 17 profiles) is rich but barely connected to the loops: only learnings-pass fans out via the Task tool, and only interview-prep (a skill) spawns parallel subagents. The Workflow tool is used nowhere.

## Inventory: recurring loops (cron-driven `claude -p`)

| Loop | Cadence | Model | Internal architecture | Gate before claims? |
|------|---------|-------|----------------------|---------------------|
| autonomousDev `run.sh` | daily 7am | Opus | single agent; bash gathers repo state | YES: deterministic `verify.sh` (real build/test) + human Discord approval |
| fix-checker `run.sh` | Sun pre-reset | Sonnet | single agent; self-merges to main | **NO deterministic gate** (soft in-prompt only) |
| supervisor `run.sh` | daily | Sonnet | single agent; reads score files | n/a (analysis only) |
| learnings-pass `run.sh` | every 8h | Sonnet | **fans out via Task tool** (Verifier/Drafter/Deep-analysis) | self-verifies in-session |
| doc-sync-pass | every 4h | Sonnet | single agent | n/a |
| claudemd-audit | weekly | Opus | single agent over all CLAUDE.md | n/a |
| review-gemini-prs | every 20m | Sonnet | **serial loop**, one claude call per draft PR | per-PR verdict |
| security-scanner | daily | Haiku→Sonnet | two serial passes (broad scan, then verify) | escalation pass |
| job-pipeline | daily | Claude CLI | **serial loop**, one call per job (cover letter/outreach) | none |
| auto-shorts learning | per analytics | Claude CLI | **serial loop**, one call per channel | none |

## Subagent library (defined, mostly unused by loops)

- `~/.claude/agents/`: architect, debugger, doc-sync, propagation, quick-search (haiku), reviewer, security, and now **verifier** (added 2026-06-23). NOTE: this directory is not version-controlled.
- `agentGuidance/profiles/`: 17 specialist profiles (architect, backend, critic, data, debugger, devops, doc-sync, frontend, gtm, implementer, pm, propagation, qa, reviewer, security, testing, useradvocate).
- Actual multi-agent usage found: learnings-pass (Task fan-out), interview-prep skill (one research subagent per company), onboard skill (one Explore agent). Everything else is single-agent.
- Workflow tool: zero usage anywhere in `~/.claude` or `claude-skills`.

## Key architectural facts

- The autonomous loops are single `claude -p` invocations. They CAN spawn subagents via the Task tool from inside that one headless session (learnings-pass proves this works under `--dangerously-skip-permissions`). The reliable pattern is the Task tool with an inline role description, not a custom agentType reference (custom agentType resolution in headless mode is not guaranteed).
- The Workflow tool runs inside an interactive/SDK session, so it does not drop into a bare `claude -p` cron. For cron loops, parallelism comes from bash (`&`/`wait -n`, `xargs -P`) or in-prompt Task fan-out. Workflow is for interactive heavy tasks (`/code-review ultra` and `/deep-research` already use that shape).
- The live runner repo (`autonomousDev-private`) executes from its working tree directly. Edits to `prompt.md` / `*.sh` take effect on the next cron fire without a deploy step.

## Recommendations (priority order)

1. **Independent verifier in fix-checker (DONE 2026-06-23).** Added a mandatory Verification Gate to `fix-checker/prompt.md`: before writing `STATUS: fixed` or merging, spawn a `verifier` subagent (inline-described) that re-runs the falsifying command and tries to refute. Added a reusable `~/.claude/agents/verifier.md` skeptic definition and a lighter verifier step in `run.sh/prompt.md` for crash/logic fixes (complements the existing deterministic `verify.sh`).
2. **Parallelize the serial N-item loops.** `review-gemini-prs.sh` converted to a 3-phase design (DONE 2026-06-23): gate serial → review PARALLEL (max 4 concurrent claude calls) → apply verdicts serial (all gh mutations + state writes race-free). Same pattern applies to job-pipeline (ThreadPoolExecutor) and auto-shorts learning (p-limit). Token gate already protects spend.
3. **Connect the profile library to the analytical loops.** supervisor and claudemd-audit are natural homes for parallel specialist perspectives (architect/reviewer/qa/security) then synthesis. 17 profiles exist; the fleet uses ~2.
4. **Adopt the Workflow tool for interactive heavy work**, not the crons. Best fits: deep reviews, multi-source research, large migrations.

## Discipline notes

- Do NOT fan out single-context analytical passes that read a handful of files (supervisor reading 7 score files gains nothing). The wins are (a) verification subagents for correctness and (b) parallel fan-out for true N-independent-item loops.
- Concurrency must never share non-atomic state. The gemini-PR reviewer parallelizes only the read-only Claude calls; every `gh pr close/ready` and `STATE_FILE` write stays serial. Naive parallelization would have corrupted the jq read-modify-write state file.

## Open items

- `~/.claude/agents/` is unversioned; `verifier.md` is live but not backed up. Decide a sync home (a repo + symlink, or add to claude-skills sync).
- `autonomousDev-private` was on a learning-agent branch (`claude/learnings-780-suggestions`) with uncommitted agent state when these edits were made; the prompt/script changes need committing onto the correct branch.
