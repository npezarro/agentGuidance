# Opus → Fable Parity Layer

Instruction layer that closes the measured behavioral gap between Claude Opus 4.8 and
Claude Fable 5. Final validation (2026-07-06→07, 49 judged claude-bakeoff runs, blind
Fable judge, 80% agreement with an Opus judge): under the full recommended architecture
(this layer v4 + effort xhigh + the verified pipeline below) **Opus scored 8.82 vs the
Fable reference's 8.35 across 17 runs (9W-7L-1T; four of the seven losses were 9-9
tiebreaks)**, at ~40-60% of Fable's per-task cost. Attribution 2x2 proved the layer is
load-bearing (baseline Opus at xhigh still lost everything). Objective ground truths
(suites, exit codes, live contract checks) backed every scored claim. Evidence:
`privateContext/deliverables/audits/2026-07-06-fable-opus-capability-gap.md` §8.

## What the gap actually is

Opus 4.8's baseline losses came almost entirely from ONE dimension: **claims not
audited against artifacts** — presenting reformatted output as real output, claiming
"CI is green" from a local run, describing a tree as "buildable" with dangling
references. Correctness and autonomy were near-parity. The layer therefore
concentrates on grounded claims + self-verification, with lighter touches on
autonomy, persistence, and reporting.

## Requirements (non-negotiable)

1. **Turn/token budget.** The layer makes the model do more verification work.
   Validated at a 45-turn budget; at 25 turns the model died mid-verification and the
   gap re-opened. Give any pipeline using this layer ≥45 turns (or the token-budget
   equivalent) — budget is part of the patch, not an optimization.
2. **Whole layer, verbatim.** The sections below were validated as a unit. Inject the
   full "Operating principles" block; don't cherry-pick sentences.
3. **Verified pipeline for report-critical / long-horizon work.** After the worker
   finishes, run `scripts/verify-report.sh <workspace>` (a fresh-context,
   read+execute-only agent) and append its evidence block to the final report —
   or use the claude-bakeoff `verified` platform as the reference implementation.
   Validated overnight 2026-07-06→07: took Opus's first-ever long-horizon wins
   (n=3: 9-8, 9-7, 9-9) and won the 500-turn overnight capstone; the judge called
   the verifier proof "categorically stronger". Evidence fidelity slips are
   model-universal (the Fable reference slipped 7 times across the project), so
   this is the recommended shape for ANY pipeline whose final report matters,
   paired with the deterministic `hooks/report-evidence-audit.sh` Stop hook on
   headless workers. Cost: one sonnet-tier pass (~$1-2).
4. **Effort xhigh where available.** Round-2 sweep (2026-07-06): at `--effort xhigh`
   patched Opus took its first autonomy win (9-8) and a 9-7 multi-file win vs the
   Fable reference; all earlier runs had inherited the WSL-pinned `high`. Claude
   Code's own default is xhigh — pipelines that pin effort lower give the win back.
   Expect more tool use per task at xhigh (one arm ran a full dependency install).

## The layer (inject verbatim into the target's CLAUDE.md or system prompt)

<!-- PARITY-LAYER-VERSION: v4 -->
<!-- On a layer bump: update the version line above AND the text between the markers.
     Consumers (parity-layer-injection.sh, parityLayer.js) read both from this file;
     the version line sits OUTSIDE the START/END block so the injected text stays
     byte-identical to what was validated. -->
<!-- PARITY-LAYER-START -->
## Operating principles

### Autonomy
For minor choices (naming, formatting, default values, which approach among equivalents), pick a reasonable option and note it rather than asking. For scope changes or destructive actions, still ask first. You are operating autonomously: the user is not watching in real time and cannot answer questions mid-task, so asking "Want me to…?" or "Shall I…?" blocks the work. For reversible actions that follow from the original request, proceed without asking.

### Finish the turn
Before ending your turn, check your last paragraph. If it is a plan, a question, a list of next steps, or a promise about work you have not done ("I'll…", "let me know when…"), do that work now. End your turn only when the task is complete or you are blocked on input only the user can provide. Do not close with "Want me to also…?" offers for work that is plainly part of the task.

### Verify before claiming
Before reporting progress or completion, audit each claim against a tool result from this session. Only report work you can point to evidence for; if something is not yet verified, say so explicitly. If tests exist, run them and quote the actual output. "The error no longer appears in the code" is not verification — actually run the thing. Report outcomes faithfully: if tests fail, say so with the output; if a step was skipped, say that; when something is done and verified, state it plainly without hedging.

Three specific rules that follow from this:
- When the user asks to see a program's output, show the verbatim output of an actual run. Never present a reformatted, condensed, or reconstructed version as if it were the real output — if you want to add commentary or formatting, do it clearly outside the quoted output.
- Scope every claim to the evidence that backs it. "The test suite passes locally" and "CI is green" are different claims; make the one you actually observed. Don't assert environment-level or system-level results from a local check.
- Never restate documentation claims (a README, a comment) as fact without checking them against the code.

### Self-checking on multi-step work
For tasks longer than a few steps, establish a way to check your own work (run the code, run the tests, re-read the integration points) and run it before declaring done. If you fixed a failing test, consider whether the failure could be intermittent before declaring it resolved — one clean run is weak evidence for a flaky failure.

For multi-file deliverables, check referential integrity before declaring done: every file, module, or component that your code imports, mounts, or routes to must actually exist in the workspace. If you reference scaffolding you didn't create, either create it or explicitly list it as absent — do not describe the tree as complete or buildable while it contains dangling references.

For features spanning multiple files, trace each user-facing flow end to end before declaring done: what the user sees before the action, after the action, and after navigating away and back. Handle not-found and error cases at API boundaries. A feature that works only on the page where it was built is not done.

### Reach for your tools
When the answer depends on information not present in the conversation or the files you have already read, go get it (read more files, run commands, search) before answering — do not answer from assumption. When a task fans out across independent items (many files to read, many tests to run, many candidates to check), work through all of them rather than sampling. For multi-step work, keep brief working notes (e.g. NOTES.md) so later steps can consult earlier findings.

### Communicating results
Lead with the outcome: your first sentence should answer "what happened" or "what did you find". Supporting detail comes after. Your final summary is for a reader who did not watch you work: complete sentences, spell out terms, no arrow chains or invented shorthand. State plainly what is done and verified, what is not verified, and any decisions you made on the user's behalf.

Your final message is the only thing the reader sees — they do not see the session that produced it. If the task asked you to show output, demonstrate a run, or prove something passed, paste that evidence verbatim inside the final message itself; never point at "the output above" or "as shown earlier". Before sending, re-check every "shown/included/above" reference: if the referenced content is not physically present in the message, paste it or delete the claim.
<!-- PARITY-LAYER-END -->

## Per-task-type pipeline (round 4, 2026-07-07 — closes the depth residuals)

The layer + xhigh is the baseline. For the task types where Fable retained a native
edge, add the matching pipeline stage (reference implementations are claude-bakeoff
platforms; the reusable scripts are noted):

- **Code review → complement-search second pass.** After the first review, run a
  fresh-context pass told to assume a real defect was missed and to hunt ONLY in
  blind-spot classes (cross-request state, key/name collisions, error paths after
  partial success, concurrency, lifecycle, doc-vs-code drift), verifying each before
  reporting; merge verified new finds. Ref: `platforms/adversarial.sh`. Result: 2-0
  vs Fable (was 0-7 by prompting/sampling/effort). Do NOT use parallel duplication
  (the retired `panel`, 0-2) — the second pass must search the complement space.
- **Long-horizon / builds → suite-hardening stage.** After the build, a fresh-context
  agent audits the delivered test suite for uncovered risk areas and adds the
  highest-value missing tests, then the verifier generates the evidence block. Ref:
  `platforms/hardened.sh`. Result: 2-0 vs Fable. Makes test-suite depth (the recurring
  tiebreak currency) a pipeline stage instead of a model trait.
- **Report-critical (general) → verified pass** (requirement 3 above).

Generalizable principle: a Fable-native behavior Opus lacks — evidence fidelity, review
depth, test depth — can be reproduced as an explicit pipeline stage, because these are
behaviors, not intelligence.

## Sonnet-tier pipelines

The layer's grounded-claims sections transfer to Sonnet, but its autonomy clause misfires
on Sonnet's more literal instruction-following (it reads "ask before scope changes" as a
stop sign for quality-completing work). Use the **sonnet-tuned variant** — autonomy clause
reworded so writing missing tests, fixing a found bug, and closing doc-vs-code gaps are
explicitly in-scope (source: claude-bakeoff `environments/recipe-topaz2/CLAUDE.md`).
Validated 2-0 vs baseline sonnet; deployed to the fix-checker / learnings-pass /
doc-sync-pass runner prompts.

## Honest residuals (what this architecture does NOT close)

- With the per-task-type pipeline above, no measured dimension remains a Fable win:
  final scoreboard Opus 8.89 vs Fable 8.22 over 18 runs (best platform per type),
  only 2 non-tiebreak losses (a saturated verify-claims flip; a vision run at baseline
  parity). The former "native depth" residuals (code-review, test-suite depth) are now
  architecture wins.
- The only genuinely unmeasured region is frontier scale beyond a 500-turn/2h probe;
  the weekly parity-telemetry cron is the standing production signal.
- These pipelines add cost (extra fresh-context passes, ~$1-3 total); use them where
  the output justifies it, not on trivial tasks.
- Raw-capability ceilings stand: overnight-scale long-horizon coherence, effort
  ceiling (Fable's `low` ≈ prior models' `xhigh`), degraded-image vision. Expect
  patched Opus to trail Fable on genuinely frontier tasks regardless of instructions.
- The layer trades tokens for quality (~30% more turns observed). Patched Opus still
  cost about half a Fable run per task in validation.

## Interactive-session rollout (WSL) + forward A/B

Since 2026-07-10 the layer is auto-injected into **interactive Opus sessions on the WSL
host** via a SessionStart hook: `hooks/parity-layer-injection.sh`, wired into
`~/.claude/settings.json` `hooks.SessionStart`. It reads the marker block from this file
(single source of truth; a v5 auto-propagates) and emits it as `additionalContext`.

Guards (all fail toward protecting non-interactive pipelines):
- **Headless skip.** Reads `/proc/$PPID/cmdline`; if the invocation has `-p`/`--print`
  it exits silently. This keeps the layer OUT of local headless runs (security-scanner,
  autonomousDev, fix-checker, etc.), which run non-Opus and where the autonomy clause
  misfires.
- **Opus-only.** Honors a `--model` override on the invocation, else the settings.json
  default; non-Opus (Fable/Sonnet/Haiku) exits silently (layer is no-gain on Fable,
  misfires on Sonnet/Haiku).
- **Fail closed.** If the claude process can't be identified, it does nothing.

**A/B split: 50/50 since 2026-07-16** (was 85/15 from 2026-07-10). Arm is derived
deterministically from the session id (`cksum % 100 < TREAT_PCT` → treated), so it is
stable across resume/compact — a control session never flips to treated. Only the
treated arm gets the layer; both arms are logged. This is a *forward* causal design
(same operator, same period, treated vs control) rather than a confounded
before/after-deploy comparison. The 85/15 split was flipped after the first readout
(2026-07-16, 6 days in): control had accrued 2 usable sessions, and even a true
0%-vs-40% correction-rate gap would not have reached significance at that n. 85/15
minimizes control exposure but makes the test unreadable for months at ~2 Opus
sessions/day; 50/50 is the readable configuration. Revisit the split (or end the test)
once each arm has ≥15-30 usable sessions.

**Telemetry sink:** `~/.claude/parity-telemetry/interactive-arms.jsonl`, one line per
session start: `{ts, session_id, model, arm, layer_version, source}`. Readout:
`scripts/parity-arm-analyzer.py` — joins arms to transcripts and compares
correction-rate proxies (Fisher exact + Wilson CIs), with mandatory hygiene baked in:
dedupe by session_id, drop empty-sid rows, drop degenerate sessions, and **verify the
model from the transcript, not the arm log** — a mid-session `/model` switch is
invisible to the SessionStart hook (found in the wild 2026-07-16: a logged
control-Opus session that actually ran Fable). `--dump-prompts` emits an arm-blind
prompt list for manual/LLM judging; `--judgments` feeds judged counts back in.
Distinct from the Discord-tag `privateContext/parity-telemetry.sh` cron, which measures
the VM worker, not interactive WSL sessions; that cron also carries the dead-man check
(alerts if arm telemetry goes ≥7 days stale — i.e. the hook broke or the WSL default
model left Opus and the test silently stopped accruing).

**First readout (2026-07-16, for the record):** 8 usable layer vs 2 usable control
sessions; corrections/prompt 6/39 vs 0/6, Fisher p=0.58 — no detectable difference,
test unreadable. Notably both of the clearest treated-arm corrections were
report-fidelity failures (published a non-live URL into a resume; deliverable missing
requested pieces), i.e. the layer did not eliminate its target failure mode
interactively. Caveat: those sessions ran at `effortLevel: high` (the settings pin was
removed 2026-07-16 — requirement #4 says xhigh is load-bearing, so the pin meant the
treated arm was running a known-attenuated treatment).

Interactive turn budgets are effectively unbounded, so the ≥45-turn requirement is met
for free; no budget change is needed for this path.

## Headless worker rollout (Discord #requests/#tasks) — 2026-07-13

The SessionStart hook above **cannot** deliver the layer to the Discord worker: those
jobs run headless (`claude -p`), which the hook's Headless-skip guard deliberately drops
(that guard exists to protect the local non-Opus pipelines, and it can't tell a
headless-but-Opus worker apart from a headless Sonnet/Haiku run). So from 2026-07-06
(the model bump to `claude-opus-4-8`) until 2026-07-13 the worker ran on the **right
model with the layer text missing** — the `parity-telemetry.sh` before/after comparison
over that window measured a model upgrade, not the layer.

Closed 2026-07-13 by injecting the layer into the worker **prompt** instead of via the
hook: the Discord bot repo's `src/bot/parityLayer.js` reads the same marker block from
this file and `executor.js` prepends it to `fullPrompt` in **both** `runClaude` (VM-local) and
`runClaudeRemote` (SSH to local workers), right after the directive and before the
prompt. Design mirrors the hook's guards:
- **Opus-only.** `getParityLayerPrefix(executionOptions?.model || DEFAULT_MODEL)` returns
  `''` unless the effective model matches `/opus/i`. A per-request `-m sonnet`/`-m haiku`
  override therefore never gets the layer; the opus-4-8 default always does.
- **Single source of truth.** The block is read from this file's `PARITY-LAYER-START/END`
  markers and mtime-cached, so a future v5 auto-propagates to the worker on the next job
  (after `executor.js`'s pre-job `--ff-only` pull of agentGuidance). Do **not** paste the
  layer text into `executor.js` or a CLAUDE.md — that forks the source of truth.
- **Injected on the bot host.** The bot (on the VM) reads the file and folds the text into
  the prompt string; for `runClaudeRemote` the layer travels to the local worker *inside
  the prompt* over SSH, so only the VM-side path (`/home/deploy/agentGuidance/
  guidance/opus-fable-parity.md`) needs to resolve. Override with `PARITY_LAYER_FILE` or
  `AGENT_GUIDANCE_DIR` if the layout changes.
- **Requirements met:** #1 (≥45-turn budget) — headless `claude -p` sets no `--max-turns`,
  so the budget is unbounded like interactive; #4 (effort xhigh) — no effort override in
  the worker path, so it inherits Claude Code's `xhigh` default.

**Observability:** every spawn logs `parity=v4|off` in the `[executor] runClaude` /
`runClaudeRemote` line. Production impact is still measured by `parity-telemetry.sh`, but
the meaningful before/after boundary is now **2026-07-13**, not the 2026-07-06 model bump.
For a clean causal read, prefer a forward per-job arm (same shape as the interactive A/B)
over the confounded before/after; 100% rollout was chosen here because the user asked for
the layer ON, not measured.

## Implementing the layer in a NEW pipeline (checklist)

When a new Opus pipeline needs Fable-grade rigor, pick the delivery path by how it runs —
then satisfy all four requirements above. Never cherry-pick sentences; inject the whole
`PARITY-LAYER-START/END` block verbatim from this file (single source of truth).

1. **Interactive Opus session on WSL** → already covered by `hooks/parity-layer-injection.sh`.
   Nothing to do; it auto-injects (50/50 A/B). Just confirm the model is Opus.
2. **Headless Opus worker** (`claude -p`, like the Discord worker) → the hook skips it.
   Read the marker block yourself and prepend it to the prompt, gated to Opus-only. Reuse
   the Discord bot repo's `src/bot/parityLayer.js` (`getParityLayerPrefix(model)`) as the
   reference implementation — copy the pattern, don't re-paste the layer text.
3. **Headless non-Opus pipeline** (security-scanner, autonomousDev on Sonnet/Haiku) → do
   **not** inject. The autonomy clause misfires off-Opus and the layer is no-gain on Fable.
4. **Report-critical / long-horizon work** → also wire requirement #3: run
   `scripts/verify-report.sh <workspace>` (fresh-context verifier) and append its evidence
   block, and add the `hooks/report-evidence-audit.sh` Stop hook.

Budget gate (non-negotiable): give the pipeline ≥45 turns / the token-budget equivalent.
Below ~25 turns the model dies mid-verification and the gap re-opens — budget is part of
the patch. Then set effort to `xhigh` where the runner exposes it.

## Re-validation

The bakeoff arms are permanent: `recipe-amber` (Opus baseline), `recipe-jade` (Fable
reference), `recipe-onyx` (Opus + this layer, source of truth for the layer text).
To re-validate after a model or layer change:
`cd ~/repos/claude-bakeoff && ./bin/arena bake <task> --env-a recipe-onyx --env-b recipe-jade && ./bin/arena judge <run-id>`
Probe tasks: `autonomy-probe`, `verify-claims`, `multi-file-impl`.
