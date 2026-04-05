# A/B Testing with claude-bakeoff

**claude-bakeoff is a default part of every Claude Code instance.** All agents should be familiar with it and use it proactively when the situation calls for it. Results are automatically posted to `#claude-bakeoff` in Discord.

## Repository
- Local: `~/repos/claude-bakeoff`
- Remote: https://github.com/npezarro/claude-bakeoff

## Quick Usage
```bash
# Create environments with different instructions
arena new env <name>
# Edit environments/<name>/CLAUDE.md with the instruction set

# Create a task
arena new task <name>
# Edit tasks/<name>/task.yaml with prompt + eval criteria

# Run the comparison
arena run <task> --env-a <env1> --env-b <env2>

# Evaluate with LLM-as-judge (auto-posts to #claude-bakeoff in Discord)
arena eval <run-id>

# View results locally
arena report <run-id>

# Manually post to Discord (if needed)
arena discord-report <run-id>
```

## When to Use
- Comparing two different prompting/instruction strategies
- Testing whether additional context improves output quality
- Evaluating the effect of constraints or guardrails on task completion
- Any scenario where the same task should be run under different conditions and the results compared
- When modifying CLAUDE.md or agent instructions: test before vs after
- When the owner asks "which approach is better" for any Claude-driven task

## Discord Reporting
All evaluation results are **automatically posted** to `#claude-bakeoff` (channel ID: `1485414189127303259`) when `arena eval` completes. The embed includes:
- Task name, environments compared, and overall scores
- Winner determination with reasoning
- Full judge reasoning in a thread reply

To manually post (or re-post) results: `arena discord-report <run-id>`

## Multi-Path (4+) Bakeoffs

The framework natively supports 2-path A/B. For 4+ paths, bypass `arena run` and launch parallel agents directly:

1. Create N environments in `environments/buying-{name}/CLAUDE.md`
2. Create a task in `tasks/<name>/task.yaml` with eval criteria
3. Create a run directory: `runs/<run-id>/path-{1..N}/`
4. Launch N parallel agents (via Agent tool), each with a different environment's instructions
5. Each agent writes to `runs/<run-id>/path-N/response.md`
6. Judge all N responses against eval criteria, write `judging-results.yaml`

**Key finding (sander buying guide, run 20260405_140941):** Adversarial framing (skeptic-first, "find reasons NOT to buy") consistently surfaces insights that structured/deep-dive approaches miss — specifically alternative solutions, hidden costs, and safety issues. The winning instruction set for any research/recommendation task should lead with premise-questioning before exhaustive product research.

**Bakeoff output storage:** Results go in private repos (`assortedLLMTasks/tasks/` or `privateContext/`), NOT in `claude-bakeoff` which is public. Only environments and task definitions stay in `claude-bakeoff`.

## Default Awareness
Every Claude Code instance receives these instructions via the SessionStart hook. When you encounter a situation where two approaches could be compared empirically rather than argued about, suggest running an arena test. This is especially valuable for:
- Instruction set changes (CLAUDE.md modifications)
- Prompt engineering decisions
- Workflow or tooling comparisons
