# /goal Conditions for Headless Runners

Claude Code >= 2.1.139 supports `/goal <condition>`: the session re-prompts itself turn after turn until a small evaluator model judges the condition satisfied, then stops. In headless mode the goal string IS the prompt (`claude -p "/goal ..."`). This converts "the session decided it was done" into "the session proved it was done", which directly enforces ESSENTIAL rules 3 and 4 at the harness level.

## Where it is wired in (2026-07-16)

- `autonomousDev-private/lib/runner-lib.sh` — `runner_claude_goal` (used by the daily runner, learnings-pass, fix-checker)
- the Discord bot coordination repo — `executionOptions.goalCondition` for `!task` template jobs (VM-local and remote-worker paths; per-template `goal` field overrides the generic condition)
- Conversational request jobs stay goal-less by design: questions must not loop on a completion condition.

## The mission-file pattern

The goal condition is capped at 4000 characters, so large runner prompts cannot be inlined. Write the full prompt to a mission file, then:

```
/goal Read and execute the mission briefing at <path>. This goal is achieved when
the conversation demonstrates EITHER (a) <condition>; OR (b) a final message
beginning 'BLOCKED:' stating concretely what was attempted and why the mission
cannot be completed.
```

## Rules for writing conditions

1. **Transcript-demonstrable only.** The evaluator reads the conversation; it never runs commands itself. "All tests pass" is a bad condition; "the full test command output is pasted showing it passes" is a good one. This matches the existing verification gate: paste raw output, then claim.
2. **Always include the BLOCKED: escape hatch.** Without it, an unmeetable condition loops until the timeout kills the run and the partial work is reported as a plain failure.
3. **Cover the legitimate no-work path.** A runner that can correctly do nothing (no delta, PR cap reached) needs that outcome named in the condition, or quiet runs will loop hunting for work.
4. **Skip goals on `--resume`.** An active goal restores with the session; sending `/goal` again replaces it and orphans the original condition. All wired paths guard on this.
5. **Version-guard and fall back.** `runner_claude_goal` falls back to a plain run when the CLI predates 2.1.139 or the composed condition exceeds the cap. Copy that pattern for new consumers; a goal must never be the reason a cron produces nothing.

## Operational notes

- **Cost:** the evaluator (Haiku) is negligible, but goal runs take more turns than single-pass runs. Keep goal-wrapped crons behind `check-usage.sh` gates (they already are, via the runner harness).
- **Silence:** with default text output a headless goal run prints nothing until the condition is met. All wired consumers use `--output-format stream-json --verbose`; do the same for new ones or the run looks hung.
- **Timeouts are unchanged.** The goal loops inside the existing `timeout` wrapper; a looping goal cannot outlive the runner's time budget.
- **Stop hooks:** `/goal` registers a session-scoped prompt-based Stop hook. It is harness-managed and exempt from the tiered classification in `stop-hook-safety.md` (see the note there).
- **Requires hooks enabled** and an accepted workspace trust dialog; `disableAllHooks` disables `/goal` too.
