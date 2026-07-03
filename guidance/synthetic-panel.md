<!-- Load when: proposing, building, or shipping a user-facing product change; want structured synthetic-user feedback on an idea -->
# Synthetic Panel: Advisory User Feedback

An internal API that runs a proposed user-facing change past a panel of scenario-grounded AI personas (3 reshuffled runs, harm-gated median aggregation) and returns a KILL / ITERATE / SHIP verdict with per-persona concerns. Service docs live in the synthetic-panel repo.

## The Contract: Signal, Never a Gate

The panel exists to make work better, not to stop it. These rules are binding for every consumer (interactive sessions, autonomousDev, skills):

1. **Fail-open, always.** If the panel is down, slow, or unparseable, proceed exactly as you would have without it. `panel-check.sh` encodes this: it always exits 0 and emits `{"verdict":"UNAVAILABLE"}` on any failure. Never retry-loop on it, never wait past its timeout, never treat its absence as a reason to stop work.
2. **Run it in parallel, not in your critical path.** Start the check in the background before implementing; collect the result when writing the PR/summary. A panel run takes minutes.
3. **Verdicts are advice with one exception.** ITERATE concerns are free user-research: address the cheap ones, surface the rest. SHIP is corroboration, not permission. The one strong signal is `harmFlagged: true` (consent/privacy/legal/dark-pattern): put it prominently at the top of the PR or report with the harm reasons, and let the human decide. Never discard completed work because of a verdict.
4. **`confidence: "low"` means weak signal.** The run failed its own discrimination self-check; mention it and give the verdict little weight.
5. **Budget: one run per change.** Each run is ~57 isolated bridge calls on the alt account. Evaluate the change once, not per commit.

## How to Call It

```bash
bash ~/repos/synthetic-panel/scripts/panel-check.sh \
  --product "<one-line product brief>" \
  --change "<the change, described from the user's perspective>" \
  [--product-key shopper] [--timeout 900]
```

Output is one JSON line: `verdict`, `confidence`, `median`, `behaviorChangeFraction`, `harmFlagged`, `harmReasons`, `controlGap`, `topConcerns`, `jobId`. Describe the change as a user would experience it, not as an implementation diff; the personas react to the experience.

## When to Use It

- A new user-facing feature, flow change, or UX change in any public-facing app (before or while building).
- Evaluating a product idea before committing a build session to it.
- NOT for refactors, bug fixes, tests, docs, infra, or internal tooling; the panel models end users, who never see those.

## Calibration Duty

The harm gate applies only to what the change description **states** — not to inferred implementation details (data sourcing, logging, third-party calls, storage). Unstated potential harms go to `topConcerns`, not `harmReasons`. This was calibrated 2026-07-02 (commit `2a611e6`) to fix systematic over-flagging of benign changes (price-drop alerts, sparklines) that shared no stated consent/privacy behavior. Verified two-sided: benign changes lose harm flags; dark-pattern changes still KILL.

If you see a verdict that looks miscalibrated, record the `jobId` and the disagreement in the synthetic-panel repo's `context.md`. Calibration fixes go in the persona HARM CHECK prompt wording only; the aggregation thresholds are final by design.
