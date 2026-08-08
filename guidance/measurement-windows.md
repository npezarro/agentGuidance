<!-- Load when: auditing a logger/collector's coverage, or a metric whose denominator comes from a different source than its numerator -->
# Measurement Windows and Censored Denominators

A collector's coverage is `records / opportunities`. The numerator comes from the
log. The denominator usually comes from somewhere else (a transcript, a database,
the thing being observed). Those two sources almost never share a start time, and
when they don't, the ratio is wrong in a way that looks like a behavioural finding.

## The rule

**Align the denominator to the collector's own observation window before computing
coverage.** The window starts at the first record in *the log you are reading*, not
at the moment the collector was installed, and not at the beginning of the observed
unit's life.

```
window_start = min(ts) over the CURRENT log file
denominator  = opportunities where window_start <= ts <= window_end
```

Compute coverage both ways. If the uncorrected and corrected numbers differ, the
gap is measurement, not behaviour, and you must explain it before theorising about
the collector.

## Why the artifact is convincing

The bias is not random. It scales with how long the observed unit has been alive:
a unit that predates the window contributes its whole pre-window history to the
denominator and nothing to the numerator. So the deficit concentrates in
long-lived units.

If your segmentation variable correlates with age -- and "multi-turn vs
single-turn", "active vs idle", "power user vs new user", "long-running job vs
one-shot" all do -- the artifact arrives pre-packaged as a plausible mechanism:

> "It fires reliably on the first event and unreliably after."

That sentence is what a censored denominator sounds like. Short units are
entirely inside the window and read 100%; long units straddle it and read ~50%.
No such mechanism exists.

## A rotation you performed yourself is still censoring

The trap that makes this hard to catch: you can *know* about the rotation and
still get it wrong, because knowing it answers a different question.

- "Did the rotation lose data?" -- No, it was archived deliberately.
- "Does the denominator start where the current log starts?" -- Nobody asked.

Ruling out "log resets" as a cause of *missing writes* does not rule it out as a
cause of a *mis-specified denominator*. They are separate failures with the same
name. Check the archives explicitly: if the "missing" records are sitting in
`*.v1.jsonl` / `*.archive` / the rotated file, the collector never failed.

```bash
# The decisive check, and it is cheap. Do it FIRST.
for f in <log> <archives>; do
  echo "$f: $(grep -c "$UNIT_ID" "$f") records"
done
```

## The same censoring propagates into any per-unit join

A metric that joins a full-lifetime event set against a window-truncated record
set inherits the bug and hides it better:

```python
opened[sid]  # scanned from the WHOLE transcript, all of the unit's life
would[sid]   # built only from records in the CURRENT log
recall = len(opened & would) / len(opened)      # structurally unwinnable misses
```

Every event that happened before the log's window is a guaranteed miss, because
the record that would have matched it is in the archive. Time-bound **both** sides
of a per-unit join, or drop units whose record set is known to be truncated.

This matters most when a metric has a "if the number is low, abandon the plan"
branch: censoring only ever pushes the number down, so it manufactures false
negatives, never false positives.

## Fix every direction, not just the flattering one

When you correct a censored join, check each metric separately for **which way
its bias points**. They will not agree, and applying one bound everywhere is how
a rig quietly gets tuned toward the answer you want.

xp-001 had two metrics reading the same event set:

| metric | correct bound | why |
|---|---|---|
| recall | per-unit floor (first surviving record) | fair to the retriever: only score events whose trigger this rig actually saw |
| demand ("was it ever wanted?") | the log's global window | a fact about the user, not the retriever; the stricter floor **under-counts** it |

The recall bound raises the number. The demand bound raises it too, and the
decision rule ships when demand is zero, so tightening demand would have pushed
toward shipping on an artifact. **State each metric's bias direction out loud
before choosing its bound.**

## The freeze protects the collector, not the scorer

"The rig is frozen" usually means *stop changing what gets recorded*. A scorer
reads data that already exists; correcting it re-reads the same records and
cannot invalidate them.

Settle this with the fingerprint rather than by argument. If your records carry a
version hash, recompute it from its declared inputs and compare:

```python
h = sha256(collector_source + input_set_a + input_set_b + thresholds)
assert h.hexdigest()[:12] == recorded_rig     # scorer absent -> scorer is free
```

If the scorer is not an input, editing it changes no record and **does not
restart the observation window**. If it *is* an input, treat it as the collector.
Print the pre-fix and post-fix readings side by side either way, so the
correction is auditable instead of a number that silently moved.

## Checklist

Before reporting a coverage or recall figure:

1. What is the first timestamp in the log file I am actually reading?
2. Were there earlier log files? Do the "missing" records live in them?
3. Is my denominator filtered to `[window_start, window_end]`?
4. Does the apparent deficit correlate with the observed unit's age or duration?
   If yes, suspect censoring before suspecting the collector.
5. In any per-unit join, are both sides bounded by the same window?
6. Are the residual misses real events, or harness artifacts? (For prompt
   collectors: `/compact`, `/clear`, command-name expansions, and continuation
   summaries appear as `type:user` but never fire `UserPromptSubmit`.)

## Worked example

xp-001 (2026-08-07). Reported hook coverage was single-turn 102/102 = 100%,
multi-turn 40/77 = 52%, read as "the hook fires on a session's first prompt and
unreliably after" and logged as a validity threat.

The log had been archived at a rig freeze on 2026-08-05 at 17:47:02; the
denominator counted every prompt in each session's transcript, including prompts
from days before that. One session contributed 19 prompts and 1 record. Its other
6 records were in `memory-lazy-shadow.v1.jsonl` and `.v3-mixed.jsonl`, and its
first 2 prompts predated the hook's existence entirely.

Corrected to the log's own window, per-prompt timestamp join across all 124
transcripts: **153/153 = 100%**, single- and multi-turn alike. The 3 apparent
residuals were one `/compact` operation (the command, its expansion, and the
continuation summary). No first-prompt bias exists.

The same censoring was independently depressing the recall metric: 4 of its 8
opportunities came from the one archive-split session, and were unwinnable by
construction. Fixed in the scorer on the same day (reading moved 12% -> 25%, both
printed); the collector was not touched, and recomputing the rig fingerprint from
its declared inputs proved no record was invalidated and the window did not
restart.

Related: `guidance/debugging.md` (diagnose before retrying), `guidance/testing.md`.
