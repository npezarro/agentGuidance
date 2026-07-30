<!-- Load when: when to spawn subagents (Task fan-out / parallel bash / Workflow) vs stay single-agent; concurrency-safe 3-phase pattern -->
# When to Fan Out into Subagents

Guidance for autonomous loops and interactive sessions on when to spawn subagents (Task tool / parallel `claude -p` / Workflow) versus staying single-agent. The default is single-agent. Fan out only when the task structure genuinely benefits.

## The three primitives, and where each applies

1. **In-session Task fan-out** — a single `claude -p` session spawns subagents via the Task tool. Works in headless `--dangerously-skip-permissions` sessions (learnings-pass proves it). Use the Task tool with an INLINE role description; do not rely on a custom agentType name resolving in headless mode. This is the only fan-out available to a cron `claude -p` loop.
2. **Bash-level parallelism** — `&` + `wait -n` throttle, or `xargs -P`. Use when a loop calls `claude -p` (or any subprocess) once per independent item. Cron-friendly, no SDK needed.
3. **Workflow tool** — deterministic multi-agent orchestration (fan-out, pipeline, adversarial verify, synthesize). Runs inside an interactive/SDK session, NOT a bare cron `claude -p`. Use for interactive heavy work (deep review, multi-source research, migrations).

## Fan out when

- **An independent claim needs an independent check.** Before a loop reports "fixed / passing / works" — especially a loop that self-merges or deploys — spawn a verifier subagent that RE-RUNS the falsifying command and tries to refute. This enforces ESSENTIAL #3 (Verify Before Asserting) and #5 (Test Before Reporting). A skeptic with fresh context catches what the author rationalized.
- **N genuinely independent items are processed one at a time.** A `for item in list; do claude -p ...; done` where items do not depend on each other (per-PR reviews, per-job cover letters, per-channel analysis, per-repo audits). Parallelize the expensive calls; keep shared-state writes serial.
- **A finding touches 3+ repos, architecture, or security.** Spawn a deep-analysis subagent to trace the full impact chain before acting (the learnings-pass escalation pattern).
- **A decision benefits from diverse perspectives.** Spawn architect/reviewer/qa/security specialists in parallel on the same artifact, then synthesize (the profile library exists for this).

## Stay single-agent when

- The task touches a handful of files in one context (supervisor reading a few score files gains nothing from fan-out).
- Work requires sequential discovery before it can be decomposed.
- The item count is small and each call is cheap (fan-out overhead exceeds the saving).
- A deterministic check already exists. A real `npm run build` gate beats an LLM verifier for build/test; reserve the verifier for correctness the build cannot prove (root cause, logic, symptom-silencing).

## Concurrency safety (mandatory)

Parallel agents must never share non-atomic state. If a loop writes a JSON state file via jq read-modify-write, or performs irreversible mutations (`gh pr close/ready/merge`, deploys), those steps stay SERIAL. The safe shape is three phases:

1. **Gate (serial):** decide which items proceed; cheap idempotent mutations OK.
2. **Work (parallel):** the expensive, read-only calls; write each result to its own file. No shared-state writes.
3. **Apply (serial):** read results in order; perform all mutations and state writes here.

Reference implementation: `autonomousDev-private/fix-checker/review-gemini-prs.sh`.

## Cost discipline

Fan-out multiplies token spend. Gate every autonomous fan-out behind the usage check (`check-usage.sh --gate-at N`) and `log()` any coverage cap (top-N, no-retry) so silent truncation never reads as full coverage. See `reference_usage_gate_system` and ESSENTIAL rules.

## When fanning out to TEST TECHNIQUES, demand a negative control

A fan-out that asks "which of these N approaches works?" produces confident-sounding
successes that are easy to misread. Two requirements turn it into evidence:

1. **Every claimed success gets an adversarial re-run** by an agent instructed to *refute*
   it, from scratch, using only the reported reproduction command. Default to REFUTED when
   it cannot be reproduced. (Already covered above — this is the same rule applied to
   technique discovery rather than to bug fixes.)

2. **Require a negative control in the agent's brief.** Ask explicitly: *what is the
   cheapest change that should NOT work, and does it in fact not work?* Without it you learn
   "X worked" but not "X worked *because of Y*" — and only the second lets you build on it.

> 2026-07-29, bot-wall bypass: 20 approaches, 37 verified successes. The single most valuable
> output was not a technique. A verifier ran the control I had skipped — spoofing the
> User-Agent alone, same IP, same moment — and showed the wall came back **byte-identical**
> (15,195B both times), while a real browser TLS fingerprint returned 440,804B of real page.
> That is what identified TLS/JA3 as the mechanism. Without it I had a working trick and no
> model, and would have built the wrong abstraction (a per-host profile map that later
> evidence showed would rot silently).

Two failure modes to brief agents against explicitly, both of which bit in that run:

- **Fabricated test fixtures.** An invented product ID / URL returns a genuine 404 and reads
  as "blocked", sending the whole investigation down a false path. Control URLs must come
  from the real data source (the production DB, a sitemap), never from memory or typing.
- **Self-inflicted rate limiting.** Bursting a target during testing turns a working
  technique into an apparent failure. Instruct agents to pace and to re-test after a cooldown
  before declaring something impossible.

---

## Persist what agents return (2026-07-30)

A subagent's report exists in exactly one place: the tool result in your context. If you
distill it into a smaller deliverable and let the raw report go out only in your chat
response, **the detail is gone** the moment the turn ends. Chat is not storage. It is not
greppable, diffable, or linkable, and a long response can be truncated in the live view.

> 2026-07-30, summarizing four conference talks: two subagents read a 112-minute and a
> 47-minute transcript and returned dense, timestamped, verbatim-quoted reports. I wrote a
> condensed synthesis to a `.md`, committed that, and let both raw reports go out only in
> the Discord response. Nick's next message was "Push those summarizations to a .md for me
> to review there." The reports were more detailed than the synthesis and had to be
> reconstructed from context rather than read back from disk.

Rules:

- **Write each substantial subagent report to a file in the same turn**, alongside (not
  instead of) whatever synthesis you produce. `agent.md`'s "Large outputs go to files" rule
  covers this.
- **One file per agent when they cover parallel items**, plus a `README.md` index. Do not
  merge N reports into one file and lose the per-item structure the fan-out bought you.
- **Commit the source too** when the work cites one (transcript, dataset, page dump, query
  output). It is usually small relative to its value, and it is what keeps every quoted
  claim re-checkable with `grep` instead of trusting the summary.
- **Verify delegated claims before publishing.** Require verbatim quotes with locators
  (timestamps, line numbers, file paths) in the agent's brief, then spot-check the load-bearing
  ones yourself. Zero-counts ("term X never appears") are worth re-running directly — they are
  the easiest claim for an agent to get wrong and the most damaging to assert.
