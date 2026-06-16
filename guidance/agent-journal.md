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

## Critical Gotcha: `journal-post.sh` Takes Exactly Two Arguments

The script signature is `journal-post.sh "<category>" "<entry text>"` — exactly two positional arguments. Passing three arguments silently corrupts both the category and the body:

```bash
# WRONG — three args: category gets validated as "trading-agent" (invalid → defaults to "observation"),
# body becomes "discovery", and the actual summary (arg 3) is silently dropped
"$JOURNAL_SCRIPT" "trading-agent" "discovery" "Trading run summary..."

# CORRECT — two args: category first, full body second
"$JOURNAL_SCRIPT" "discovery" "Trading run summary..."
```

**Why:** `journal-post.sh` validates arg 1 against `VALID_CATEGORIES`. An invalid category silently defaults to `"observation"`, arg 2 becomes the entire body, and arg 3 is ignored. No error is emitted (`stderr 2>/dev/null`), so the corrupt entry appears normal in session context. This caused trading-agent to emit 10+ blank journal entries (`"observation\ndiscovery"`) over several weeks before the bug was traced to the call site (`trading-agent cfccf16`, 2026-06-01).

**How to verify:** If your script always emits journal entries with body `"discovery"` or another category name as the text, count the arguments being passed.

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
