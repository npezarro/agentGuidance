# The Opus → Fable Parity Process

A readable companion to `guidance/opus-fable-parity.md`. That file is the terse,
load-on-demand rulebook (and the source of truth for the injected layer text); this
document explains the *process* end to end: what problem it solves, how the gap was
measured, what the fix is, how it is deployed, and how to re-validate it. If you only
read one file to *use* the layer, read the guidance. If you want to understand *why the
process is shaped the way it is*, read this.

## 1. The problem

Claude Fable 5 is the reference model for autonomous coding work. Claude Opus 4.8 is
cheaper (~40–60% of Fable's per-task cost in this workload) and, on raw correctness and
autonomy, near-parity. The question the process answers: **can an instruction + pipeline
layer close the measured behavioral gap so Opus is a drop-in for Fable on most tasks,
at roughly half the cost?**

The answer, validated over 49 judged head-to-head runs, is yes for every measured
dimension — but only under a specific architecture. The layer alone is not enough; it
needs a turn budget, an effort setting, and (for report-critical work) a verification
pass. Those are requirements, not options.

## 2. How the gap was measured

The measurement harness is `claude-bakeoff`: three permanent, pinned environments run
the same task, and a blind judge scores the transcripts.

- `recipe-amber` — Opus 4.8 baseline (no layer)
- `recipe-jade` — Fable 5 reference
- `recipe-onyx` — Opus 4.8 + the parity layer (source of truth for the layer text)

Every scored claim was backed by an **objective ground truth**: a test suite, an exit
code, or a live contract check, not the judge's taste. The judge was run blind, and an
Opus judge cross-checked the Fable judge (80% agreement) to control for judge bias. A
2×2 attribution design (layer on/off × effort high/xhigh) proved the layer is
load-bearing: baseline Opus at xhigh still lost across the board, so the wins come from
the layer, not just from spending more compute.

**Headline result (2026-07-06→07, 17 runs under the full architecture):** Opus 8.82 vs
Fable 8.35, 9 wins / 7 losses / 1 tie — and four of the seven losses were 9–9 tiebreaks.
With the per-task-type pipeline stages added (best platform per type, 18 runs): Opus 8.89
vs Fable 8.22, only 2 non-tiebreak losses.

## 3. What the gap actually was

Opus's baseline losses came almost entirely from **one dimension: claims not audited
against artifacts.** Concretely:

- presenting reformatted or reconstructed output as if it were the real program output
- claiming "CI is green" on the strength of a *local* run
- describing a multi-file tree as "buildable" while it still contained dangling
  references to scaffolding that was never created

Correctness and autonomy were already close to Fable. So the layer concentrates almost
entirely on **grounded claims and self-verification**, with lighter touches on autonomy,
persistence, and result reporting. This is the central insight of the whole process: the
gap was a *behavior* (evidence discipline), not an *intelligence* deficit — and behaviors
can be reproduced with instructions and pipeline stages.

## 4. The fix, in three layers

### 4a. The instruction layer (always, verbatim)
A single "Operating principles" block injected verbatim into the target's system prompt
or `CLAUDE.md`. Its sections: Autonomy, Finish the turn, Verify before claiming,
Self-checking on multi-step work, Reach for your tools, Communicating results. It was
validated as a *unit* — cherry-picking sentences was not tested and is not supported. The
canonical text lives between the `<!-- PARITY-LAYER-START/END -->` markers in the
guidance file; everything downstream (the injection hook, a future v5) reads from there.

### 4b. The non-negotiable requirements
The layer only works inside an envelope:

1. **Turn/token budget ≥ 45 turns.** The layer makes the model do more verification
   work. At 25 turns it died mid-verification and the gap re-opened. Budget is part of
   the patch. (Interactive sessions are effectively unbounded, so this is free there.)
2. **Whole layer, verbatim.** See above.
3. **Verified pipeline for report-critical / long-horizon work.** After the worker
   finishes, a fresh-context, read+execute-only agent (`scripts/verify-report.sh`)
   re-checks the claims and appends an evidence block. This took Opus's first
   long-horizon wins and won the 500-turn overnight capstone. Pair it with the
   deterministic `hooks/report-evidence-audit.sh` Stop hook on headless workers.
4. **Effort `xhigh` where available.** At xhigh, patched Opus took its first autonomy
   and multi-file wins. Pipelines that pin effort lower give the win back. (Claude
   Code's own default is xhigh.)

### 4c. Per-task-type pipeline stages
For the few task types where Fable kept a native edge, add the matching stage — each is
a *behavior reproduced as an explicit step*:

- **Code review → complement-search second pass.** A fresh-context pass told to assume a
  real defect was missed and to hunt only in blind-spot classes (cross-request state,
  key/name collisions, error paths after partial success, concurrency, lifecycle,
  doc-vs-code drift), verifying each find before reporting. Ref `platforms/adversarial.sh`.
  Turned a 0–7 deficit into 2–0. Note: parallel *duplication* (the retired `panel`) did
  not work; the second pass must search the *complement* space.
- **Long-horizon / builds → suite-hardening stage.** A fresh-context agent audits the
  delivered test suite for uncovered risk and adds the highest-value missing tests, then
  the verifier generates the evidence block. Ref `platforms/hardened.sh`. 2–0 vs Fable.
- **Report-critical (general) → verified pass** (requirement 3).

### Sonnet note
The grounded-claims sections transfer to Sonnet, but the autonomy clause misfires on
Sonnet's more literal reading (it treats "ask before scope changes" as a stop sign for
quality-completing work). Use the **sonnet-tuned variant**, which explicitly puts writing
missing tests, fixing a found bug, and closing doc-vs-code gaps in scope.

## 5. How it is deployed

- **Non-interactive pipelines** (claude-bakeoff platforms, report workers): the layer is
  baked into the environment's `CLAUDE.md`, with `verify-report.sh` and the
  `report-evidence-audit.sh` Stop hook wired for report-critical runs.
- **Interactive sessions**: since 2026-07-10, a `SessionStart` hook
  (`hooks/parity-layer-injection.sh`) auto-injects the layer, wired into
  `~/.claude/settings.json`. It is an **85/15 holdout A/B**: the arm is derived
  deterministically from the session id (`cksum(session_id) % 100 < 85` → treated), so it
  is stable across resume/compact — a control session never flips to treated. Both arms
  are logged to `~/.claude/parity-telemetry/interactive-arms.jsonl`.

  Guards (all fail toward protecting pipelines):
  - **Headless skip** — if the invocation is `claude -p`/`--print`, exit silently. Keeps
    the layer out of local non-Opus headless workers, where the autonomy clause misfires.
  - **Opus-only** — non-Opus effective model exits silently (no-gain on Fable, misfires
    on Sonnet/Haiku). The effective model comes from a `--model` flag or the settings.json
    default, so the host must make the model *determinable*.
  - **Fail closed** — if the claude process can't be identified, do nothing.

  Process detection reads `/proc` on Linux/WSL and falls back to `ps` on darwin/BSD
  (macOS has no `/proc`; a `/proc`-only version fail-closed on every mac session).

## 6. Honest residuals

- With the pipeline stages, no measured dimension remains a Fable win. The former "native
  depth" residuals (code-review depth, test-suite depth) are now *architecture* wins.
- The genuinely unmeasured region is frontier scale beyond a ~500-turn / 2-hour probe; a
  weekly parity-telemetry cron is the standing production signal.
- Raw-capability ceilings still stand: overnight-scale long-horizon coherence, the effort
  ceiling (Fable's `low` ≈ prior models' `xhigh`), and degraded-image vision. Expect
  patched Opus to trail Fable on genuinely frontier tasks regardless of instructions.
- The layer trades tokens for quality (~30% more turns observed). Use the extra pipeline
  passes where the output justifies the ~$1–3 cost, not on trivial tasks.

## 7. How to re-validate

The bakeoff arms are permanent. After any model or layer change:

```bash
cd ~/repos/claude-bakeoff
./bin/arena bake <task> --env-a recipe-onyx --env-b recipe-jade
./bin/arena judge <run-id>
```

Probe tasks: `autonomy-probe`, `verify-claims`, `multi-file-impl`. The generalizable
principle to carry forward: **a Fable-native behavior Opus lacks — evidence fidelity,
review depth, test depth — can be reproduced as an explicit pipeline stage, because these
are behaviors, not intelligence.**

---
*Companion to `guidance/opus-fable-parity.md` (source of truth for the layer text and the
latest numbers). Evidence: `privateContext/deliverables/audits/2026-07-06-fable-opus-capability-gap.md` §8.*
