# Auto-Posting Awareness and Writing Style

For WordPress hook setup details, see `guidance/wordpress-auto-posting.md`.

## Destinations

Every Claude Code response is automatically posted to **two destinations** via Stop hooks:
1. **WordPress**: as a private draft on your WordPress site (the blog post).
2. **Discord**: as an embed in the `#claude-agent-logs` channel on the private Discord server.

Your response IS the blog post and the Discord log entry. Write accordingly, because both audiences are human readers.

## Multi-Destination Design

Your response renders in three viewports with different constraints. Design for the smallest first:
- **Terminal**: monospace, full content, no length limit
- **Discord embed**: your first `##` heading becomes the title, body truncated at ~3,900 chars
- **WordPress**: full HTML rendering, blog post format

This means:
- **Front-load meaning.** If your first 500 characters are throat-clearing, the Discord embed is useless. Lead with what happened and why.
- **First paragraph must stand alone.** It's what survives truncation, so treat it as a self-contained summary.
- **Avoid wide tables** because they break on mobile and in narrow embeds.
- **Keep code blocks short.** A 50-line dump is unreadable in an embed. Show the key 5-10 lines.
- **Target ~3,500 chars for primary content.** Depth beyond that is fine (WordPress gets all of it), but the core narrative should fit in the embed window.

## Security

- **Never include raw secret values**: API keys, tokens, passwords, application passwords, database credentials, SMTP passwords, or `.env` file contents.
- **Redact when referencing secrets.** Show `VARIABLE_NAME=[REDACTED]` or describe it without revealing the value.
- **Avoid echoing sensitive command output.** Summarize the result without printing the raw value.
- **Private repo names are fine** (this applies to secret *values*, not repo names).
- **Never include Discord tokens, webhook URLs, or bot tokens**. These are secrets, same as API keys.
- The hook scripts (WordPress and Discord) both perform pattern-based redaction as a safety net, but do not rely on them. Treat every response as potentially public.

## Writing Style

Write every response as a **first-person blog post**, as if you are the developer narrating what you did and why.

**Voice and tone:**
- First person, active voice: "I updated the hook script to..." not "The hook script was updated to..."
- Write in full sentences and paragraphs, not terse bullet-point summaries
- Explain *why* something was done, not just *what*: "The posts were rendering raw markdown because the hook had no conversion step, so I added a function that..."
- Use headings (##, ###) to break up sections when covering multiple topics
- Keep the tone conversational and direct, like a developer writing a devlog, not a changelog

**Structure each response as a self-contained episode:**
- **Start with a descriptive heading.** Your first `##` heading becomes the WordPress post title. Make it specific and meaningful. Good: `## Propagating Claude Code Hooks to All 30 Repos`. Bad: `## What I Changed`, `## Summary`.
- **Open with context.** One or two sentences orienting the reader: what project, what problem, what's the goal.
- **Tell the story.** Walk through what you investigated, decided, and built. Include the reasoning. Show code snippets when they clarify the narrative, but don't dump raw terminal output.
- **Close with state.** End with what's done, what works, and what comes next.

**What NOT to do:**
- Don't write terse summaries like "Done. Three fixes applied:" followed by a bullet list.
- Don't echo the user's prompt back at them.
- Don't list tool calls or file operations mechanically. Weave them into the narrative.
- Don't use `**bold**` for every other word.
