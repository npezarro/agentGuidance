# Supervisor Report — Run 33 — 2026-07-01

```
SUPERVISOR_REPORT:

## Daily Ecosystem Health — 2026-07-01

**Sessions scored:** 21 | **Avg quality:** 66.3% | **Health:** YELLOW

Yesterday (Jun 30): 41 sessions, ~79% avg. Today's 12-point drop is driven by
interactive and autonomousDev-private/fix-checker sessions clustering in the
early-morning unattended window (1am–5am).

---

## Violation Trends (last 24h vs 7-day avg)

7-day baseline covers Jun 24–Jun 30 (222 sessions across all agent types).

| # | Rule | 24h Rate | 7d Rate | Trend | Top Violator |
|---|------|----------|---------|-------|-------------|
| 1 | multi_destination_learning | 57.1% (12/21) | 23.0% | DEGRADING ↑↑ | Interactive (7/13) + learning-agent (3/7) |
| 2 | guidance_to_repo_files | 42.9% (9/21) | 18.0% | DEGRADING ↑↑ | Interactive (7/13) |
| 3 | verify_before_asserting | 23.8% (5/21) | 17.6% | Degrading ↑ | Interactive |
| 4 | test_before_reporting | 19.0% (4/21) | 14.0% | Degrading ↑ | Interactive |
| 5 | gather_context_before_debugging | 9.5% (2/21) | 10.8% | Stable → | Interactive |
| 6 | self_service | 4.8% (1/21) | 0.5% | Degrading ↑ | Interactive |
| 7 | mistake_postmortem | 0% (0/21) | 2.3% | Improving ↓ | — |
| 8 | deep_research | 0% (0/21) | ~0% | Stable → | — |
| 9 | auto_deep_closeout | 0% (0/21) | ~0% | Stable → | — |
| 10 | suggest_onboard | 0% (0/21) | ~0% | Stable → | — |

**Graduated rules resurging today:**
| Graduated Rule | 24h Rate | 7d Rate | Note |
|----------------|----------|---------|------|
| update_claude_md | 9.5% (2/21) | 4.5% | Hook may have coverage gaps |
| pm2_save | 9.5% (2/21) | 2.7% | Documentation-only, no hook |

**Repo hotspots (today):**
| Repo | Sessions | Violation Density | Worst Session |
|------|----------|------------------|---------------|
| autonomousDev-private/fix-checker | 5 | 80% (4/5 violated) | 0% score (3 rules) |
| finance-tracker | 1 | 100% (5 violations) | 29% score |
| discord-bot | 1 | 100% (4 violations) | 56% score |
| learning-agent runs | 7 | 43% MDL violation rate | 67% score |

---

## ESSENTIAL.md Recommendations

### Reranking

**Swap Rules 4 and 5:** test_before_reporting (19.0% today, 14.0% 7d) outpaces
gather_context (9.5% today, 10.8% 7d) by nearly 2x. Current ordering puts the
higher-rate rule below the lower-rate one.

**Graduate Rules 8, 9, 10 (EXECUTE THIS RUN):**
- Zero violations across all 7 days (222+ sessions).
- S198 (Run #829, Jun 29) already flagged these as candidates.
- The 10-rule hard cap is full; these three slots displace rules actively being violated.
- Durable homes exist: Rule 8 → `guidance/deep-research.md`, Rule 9 →
  `guidance/comprehensive-closeout.md`, Rule 10 → `/onboard` skill trigger.

**Re-promotion candidates (defer — insufficient evidence):**
update_claude_md and pm2_save both hit 9.5% today but 7d rates are 4.5% and 2.7%.
One day is too thin to re-promote into a capped list. Monitor for 3 more days; if
7d rates cross 8%, promote update_claude_md first (more systemic, broader impact).

---

## Improvement Proposals

### Proposal 1 (ESCALATION — Run 6): Add LEARNED: field to fix-checker output format

**Status:** Requires human edit access to `autonomousDev-private/fix-checker/prompt.md`.
Six consecutive supervisor runs with no action. Highest-priority unresolved item.

- **Rule:** multi_destination_learning + guidance_to_repo_files (Rules 1 & 2)
- **Violation rate:** MDL at 57.1% today (worst single-day in 7-day window).
  Every fix-checker/autonomousDev-private session today that violated MDL also
  violated GtRF — 100% co-occurrence. This is structural, not accidental.
- **Root cause:** `fix-checker/prompt.md` has a `GUIDANCE_UPDATED:` field but no
  `LEARNED:` field. Rule 1's escape clause ("only when there's a genuine learning")
  gives the agent a rational off-ramp that it consistently takes.
- **Proposed change:**

  Edit 1 — add after the `GUIDANCE_UPDATED:` line in the output format block:
  ```
  LEARNED: <propagate-learning.sh stdout here, or "no new patterns — <one-line reason>">
  ```

  Edit 2 — replace the Rule 8 escape clause:
  - Change: "Only update guidance when there's a genuine learning — not for routine fixes."
  - To: "Call propagate-learning.sh unconditionally after every run and paste its
    stdout into LEARNED:. It is idempotent — routine runs produce 'no new patterns'
    output. A blank LEARNED: field is a scoring failure."

- **Expected impact:** MDL + GtRF in fix-checker sessions drop from ~100% per-session
  density to <10%.
- **Test plan:** Observational — track MDL/GtRF in fix-checker-labeled sessions for
  5 days post-edit.

---

### Proposal 2 (CONFIRMED NEW — execute this run): Add learning-agent to MDL mandatory trigger

- **Rule:** multi_destination_learning (Rule 1)
- **Violation rate:** 3/7 learning-agent sessions today (43%). The learning-agent is
  the ironic highest violator of the learning capture rule.
- **Root cause:** Rule 1's mandatory-trigger paragraph explicitly names
  `fix-checker, autonomousDev-private, autonomous-dev` but NOT `learning-agent`.
  The agent writes to `suggestions.md` and treats that as equivalent to full propagation.
  This is a named-exclusion gap, not a comprehension failure — the rule simply doesn't
  apply to this agent by its own text.
- **Proposed change:**

  Edit 1 — ESSENTIAL.md Rule 1, mandatory trigger paragraph:
  - Change: `"fix-checker, autonomousDev-private, autonomous-dev"`
  - To: `"fix-checker, learning-agent, autonomousDev-private, autonomous-dev"`

  Edit 2 — learning-agent/prompt.md output block, add at end:
  ```
  PROPAGATED: <propagate-learning.sh stdout, or "no-op — <reason>">
  ```

- **Expected impact:** MDL violations in learning-agent drop from 43% to <10%.
- **Test plan:** Observational — track 5 learning-agent sessions post-edit.

---

### Proposal 3 (NEW): Add a Stop-hook MDL gate for unattended sessions

- **Rule:** multi_destination_learning (Rule 1)
- **Violation rate:** 57.1% today — 2.5x the 7d baseline. The spike is concentrated
  in the 1am–5am unattended window (5 of the worst-performing sessions).
- **Root cause:** MDL is purely prompt-enforced. Proposals 1 & 2 address specific
  agent prompt gaps, but the broader pattern suggests that long or complex sessions
  deprioritize propagation at closeout. There is no Stop-hook gate for MDL, unlike
  `push_before_posting` which has the `check-unpushed.sh` gate and dropped to ~0%.
- **Proposed change:** Add a Stop hook to `settings.json` that:
  1. Detects if the session made code changes (git diff --quiet).
  2. If changes exist, checks for a sentinel file written by `propagate-learning.sh`
     (e.g., `.claude/propagated-this-session`).
  3. If sentinel is absent: emits a reminder block with the propagate-learning command
     pre-filled, blocking the Stop until acknowledged.
  Pattern: mirrors `check-unpushed.sh` exactly. Implementation in
  `~/repos/privateContext/hooks/` following the stop-hook-safety.md tier model.
- **Expected impact:** Catches end-of-session MDL skips across all agent types.
  Estimated drop from 57% to <20% (handling cases not covered by Proposals 1 & 2).
- **Test plan:** Monitor MDL rate for 7 days post-implementation. Compare to
  pre-implementation 7d baseline of 23%.

---

## Profile Performance

| Profile | Sessions | Avg Score | Weakest Rule | Coaching Note |
|---------|----------|-----------|-------------|---------------|
| Interactive | 13 | 53.5% | MDL + GtRF (both 54%) | autonomousDev-private/fix-checker interactive sessions accounted for 10 of 12 MDL violations. The agent treats these as mechanical runs, not learning events. |
| Learning-agent | 7 | 90.9% | MDL (43%) | Ironically violates the rule it exists to enforce. Fix is structural: add to the mandatory trigger list (Proposal 2). |
| Fix-checker | 1 | 60% | MDL + GtRF | Single session, thin data. Consistent with autonomousDev-private/fix-checker pattern — confirms Proposal 1's diagnosis. |

---

## System Health

**Overall: YELLOW.** 66.3% avg (21 sessions) vs 79.3% yesterday and 80% on
Jun 29 (the 7d high). The drop is concentrated in interactive sessions (53.5% avg)
driven by the early-morning unattended cluster.

**Patterns of concern:**

1. **MDL spike is 2.5x the baseline.** 57.1% today vs 23.0% 7d. Not noise — this
   is the sharpest degradation in the observed window. Proposals 1 and 2 cover the
   two named structural gaps. Without Proposal 3 (Stop hook), late-night unattended
   sessions remain unguarded.

2. **Two 0% sessions.** Sessions at ~00:12 (autonomousDev-private/fix-checker) and
   ~09:43 (autonomousDev-private/fix-checker). Zero-score means the agent completed
   its task but followed zero tracked operational rules. These are fully preventable
   and both trace to the same unresolved Proposal 1 gap.

3. **Learning-agent MDL violations are a structural irony.** The agent that exists
   to capture and propagate learnings violated the propagation rule in 43% of its
   sessions today. This is fixable in a single ESSENTIAL.md line edit.

4. **Graduated rules are re-emerging.** update_claude_md and pm2_save both show
   9.5% violation rate today despite being "graduated." The CLAUDE.md drift-check
   hook apparently has coverage gaps; pm2_save has no hook at all. Monitor for 3 more
   days before re-promoting (7d rates of 4.5% and 2.7% are still borderline).

**Autonomous agent value:**
- learning-agent: High value overall (7 sessions, 90.9% avg). MDL gap is fixable.
- autonomousDev-private (standalone): 1 clean session at 100% (score-114914). Good.
- fix-checker: Currently negative-value for MDL/GtRF. Completes fixes but consistently
  fails to propagate the knowledge. Until Proposal 1 is implemented, fix-checker is
  a net learnings sink.

---

## Action Items

| Priority | Action | Owner | Blocker |
|----------|--------|-------|---------|
| CRITICAL | Edit `autonomousDev-private/fix-checker/prompt.md` — add LEARNED: field + remove escape clause (Proposal 1, run 6) | Human | Requires human write access to that repo |
| HIGH | Update ESSENTIAL.md Rule 1 to add learning-agent to mandatory trigger list | Automated | None — executed this run |
| HIGH | Graduate ESSENTIAL.md Rules 8/9/10; swap Rules 4/5 | Automated | None — executed this run |
| MEDIUM | Implement Stop-hook MDL gate (Proposal 3) | Human | Needs hook implementation in privateContext/hooks/ |
| WATCH | Re-evaluate update_claude_md and pm2_save for re-promotion after 3 more days of data | Supervisor | Insufficient evidence today |
```
