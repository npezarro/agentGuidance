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

## Node.js subprocess parallelism gotcha: `execSync` blocks

When parallelizing `claude -p` calls from Node.js, use **non-blocking `spawn`**, not `execSync`. `execSync` is synchronous — it blocks the Node.js event loop until the subprocess exits. Wrapping it in `Promise.all` gives NO actual parallelism; calls still run serially despite the async appearance.

**Wrong (serial despite Promise.all):**
```js
function callClaude(item) {
  return execSync(`claude -p "${prompt}"`, { encoding: 'utf8' })  // blocks event loop
}
await Promise.all(items.map(callClaude))  // still serial
```

**Right (actually parallel):**
```js
function callClaude(item, prompt) {
  return new Promise((resolve, reject) => {
    let output = ''
    const proc = spawn('claude', ['--print'], { stdio: ['pipe', 'pipe', 'inherit'] })
    proc.stdin.write(prompt); proc.stdin.end()
    proc.stdout.on('data', d => { output += d })
    proc.on('close', code => code === 0 ? resolve(output) : reject(new Error(`exit ${code}`)))
    proc.on('error', reject)
    setTimeout(() => { proc.kill('SIGTERM') }, 120_000)  // safety timeout
  })
}
await Promise.all(items.map(item => callClaude(item, buildPrompt(item))))  // actually parallel
```

For Python, use `concurrent.futures.ThreadPoolExecutor` with a bounded pool (env `*_CONCURRENCY`, default 3):
```python
from concurrent.futures import ThreadPoolExecutor
with ThreadPoolExecutor(max_workers=concurrency) as pool:
    results = list(pool.map(process_item, items))
```

Keep all shared-state writes (JSON files, DB, counters) on the main thread in original order after collection. Source: auto-shorts PR #76 + job-pipeline commit f749859 (2026-06-23).

## Cost discipline

Fan-out multiplies token spend. Gate every autonomous fan-out behind the usage check (`check-usage.sh --gate-at N`) and `log()` any coverage cap (top-N, no-retry) so silent truncation never reads as full coverage. See `reference_usage_gate_system` and ESSENTIAL rules.
