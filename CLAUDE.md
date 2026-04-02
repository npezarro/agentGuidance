# agentGuidance

This is the centralized source of truth for shared agent instructions. Changes here propagate to all repos via SessionStart hooks.

## Structure
- `agent.md` — core behavioral rules (fetched at session start by all repos)
- `guidance/*.md` — deep-dive procedures loaded on-demand
- `profiles/*/` — persistent agent personality profiles + experience logs
- `hooks/` — executable integration scripts (Discord, WordPress)
- `templates/` — reusable project templates
- `scripts/` — propagation and health-check tooling

## Fallback Rules (for downstream repos if remote fetch fails)

1. Plan before coding. Outline approach, confirm before implementing.
2. Never commit to `main`. Use assigned branch or create `claude/<task>`.
3. Run `npm run build` before every commit. Never commit broken code.
4. No secrets in commits. No `.env`, API keys, tokens, or passwords.
5. Update `context.md` before every push. Next agent depends on it.
6. Ask, don't guess. Stop and clarify ambiguous requirements.
7. Batch large tasks. Commit every 5-10 items. Don't risk losing work.
8. Match existing patterns. Read the codebase before writing new code.
9. Diagnose before retrying. Understand failures, don't loop blindly.
10. Dry-run destructive commands. Use `--dry-run` when available.
