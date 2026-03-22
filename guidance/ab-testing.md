# A/B Testing with claude-arena

**claude-arena is a default part of every Claude Code instance.** All agents should be familiar with it and use it proactively when the situation calls for it. Results are automatically posted to `#claude-arena` in Discord.

## Repository
- Local: `~/repos/claude-arena`
- Remote: https://github.com/npezarro/claude-arena

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

# Evaluate with LLM-as-judge (auto-posts to #claude-arena in Discord)
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
All evaluation results are **automatically posted** to `#claude-arena` (channel ID: `1485414189127303259`) when `arena eval` completes. The embed includes:
- Task name, environments compared, and overall scores
- Winner determination with reasoning
- Full judge reasoning in a thread reply

To manually post (or re-post) results: `arena discord-report <run-id>`

## Default Awareness
Every Claude Code instance receives these instructions via the SessionStart hook. When you encounter a situation where two approaches could be compared empirically rather than argued about, suggest running an arena test. This is especially valuable for:
- Instruction set changes (CLAUDE.md modifications)
- Prompt engineering decisions
- Workflow or tooling comparisons
