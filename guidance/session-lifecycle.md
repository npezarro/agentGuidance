# Session Lifecycle

Understanding how your session works — and how it ends — prevents lost work and produces better output for every audience.

## You Are Ephemeral

Your session can be killed at any moment: OOM, SIGINT, network drop, timeout. Treat every turn as potentially your last.

- **Commit incrementally.** Don't batch 10 changes into one commit at the end. Commit after each meaningful unit of work. If your session dies, the last commit is the last save point — everything after it is gone.
- **Update `context.md` as you go**, not just at the end. If you investigated something, made a decision, or hit a blocker, capture it in `context.md` before moving on. Partial context is infinitely more useful than no context.
- **Partial output must be useful.** If you're writing a 200-line file and crash at line 100, the first 100 lines should still be valid, compilable, and meaningful. Don't structure work so that early output depends on late output.

## Your Output Is Post-Processed

Your response doesn't just appear in a terminal. Stop hooks pipe it through multiple renderers:
- **Terminal** — monospace, full content visible
- **Discord embed** — title from your first `##` heading, body truncated at ~3,900 chars
- **WordPress draft** — full HTML, rendered as a blog post

Design for the smallest viewport first. The Discord embed is the most constrained — if your first 500 characters are a preamble that says nothing, the embed is useless. Front-load meaning.

### Content Architecture

- **First `##` heading = title.** It becomes the embed title and the blog post title. Make it specific: `## Fixing the Static Rendering Trap in runEval` not `## What I Did`.
- **First paragraph = lede.** This is what survives truncation. One or two sentences that tell the reader what happened and why it matters. If they read nothing else, they should get the point.
- **Full narrative = depth.** After the lede, tell the story for readers who want it. Code snippets, reasoning, tradeoffs. This is the blog post body.

### Formatting for All Viewports

- Avoid wide tables — they break on mobile and in narrow Discord embeds.
- Keep code blocks short and focused. A 50-line code dump is unreadable in an embed.
- Use headings (`###`) to break up sections. They create visual structure in all three renderers.
- Deeply nested bullet lists render poorly outside the terminal. Prefer flat lists or short paragraphs.

## Context Files Are Crash Recovery

Think of `context.md` as the human-readable equivalent of a process's state file. When a session crashes, the next agent reads `context.md` to reconstruct what was happening. If it's stale, the next session starts blind and may repeat or undo your work.

Frame every `context.md` update as crash recovery: "If I die right now, does `context.md` contain enough for my replacement to continue?"

## Session End Checklist

The core rules in `agent.md` cover the full wrap-up procedure. This is the mental model behind it:

1. **State is saved** — `context.md` reflects reality, `progress.md` has the entry
2. **Work is pushed** — committed and pushed to remote, not just staged
3. **Nothing is orphaned** — no background processes you started, no temp files, no uncommitted changes
