# A/B Testing Solutions

When asked to A/B test, compare approaches, or evaluate different instruction sets for a task, use the **claude-arena** framework.

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

# Evaluate with LLM-as-judge and view results
arena eval <run-id>
arena report <run-id>
```

## When to Use
- Comparing two different prompting/instruction strategies
- Testing whether additional context improves output quality
- Evaluating the effect of constraints or guardrails on task completion
- Any scenario where the same task should be run under different conditions and the results compared
