# Agent Journal

Cross-session async journal for sharing observations, unfinished work, and suggestions across Claude Code sessions.

## How It Works

1. During a session, call `~/repos/privateContext/journal-post.sh` to post an observation
2. At the start of every future session, recent journal entries appear as context
3. This gives you awareness of what other sessions noticed, left half-done, or suggested

## Usage

```bash
~/repos/privateContext/journal-post.sh "<category>" "<entry text>"
```

### Categories

| Category | When to Use |
|----------|-------------|
| `observation` | Something you noticed about code quality, patterns, or behavior |
| `half-done` | Work you started but couldn't finish — what's left, where you stopped |
| `suggestion` | An improvement idea for a future session to pick up |
| `blocker` | Something preventing progress that needs resolution |
| `discovery` | A finding about the codebase, infrastructure, or a tool |

### Examples

```bash
# You noticed a code smell
~/repos/privateContext/journal-post.sh "observation" "eventBus.js flushQueue retries immediately on failure with no backoff — could hammer Discord API during outages"

# You left work unfinished
~/repos/privateContext/journal-post.sh "half-done" "botlink Prisma schema migration started but not applied. Branch: feature/user-profiles. Migration file created at prisma/migrations/20260325_add_profiles.sql"

# You have a suggestion for improvement
~/repos/privateContext/journal-post.sh "suggestion" "groceryGenius Vite config should set build.chunkSizeWarningLimit to suppress warnings. Current chunks are fine, just noisy."

# Something is broken
~/repos/privateContext/journal-post.sh "blocker" "VM disk at 87% — need to clean up old Next.js .next/cache dirs before any more builds"

# You found something useful
~/repos/privateContext/journal-post.sh "discovery" "discord-bot personas.js has an unused 'data' persona defined but no matching channel — can be removed"
```

## When to Journal

- Cross-cutting observations that affect other projects or future work
- Unfinished work that another session should know about
- Infrastructure issues (disk space, broken tests, expired tokens)
- Patterns you noticed that aren't documented anywhere
- Things you tried that didn't work (save others the same dead end)

## When NOT to Journal

- Routine task completions (that's what the Discord webhook report is for)
- Things already tracked in progress.md or git history
- Trivial observations ("this file uses tabs")
- Anything that only matters for the current session
