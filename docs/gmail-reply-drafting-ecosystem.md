# Gmail Reply Drafting with Claude Code

How Claude Code drafts email replies on my behalf, end to end. Written for someone implementing a similar system in their own ecosystem.

---

## Architecture Overview

```
Discord message (or CLI prompt)
  -> Claude Code agent
  -> reads email thread (Gmail MCP)
  -> reads voice style guide
  -> drafts reply (Gmail MCP create_draft OR file in repo)
  -> user reviews draft in Gmail, edits, sends
```

There are two paths into the system:
1. **Discord**: I message `#requests` in my private Discord server. The bot dispatches a Claude Code CLI job to my local machine via SSH tunnel.
2. **CLI**: I run Claude Code directly in a terminal and ask it to draft a reply.

Both paths use the same MCP tools and the same voice/style rules.

---

## Components

### 1. Claude Code + Gmail MCP (built-in)

Claude Code ships with built-in MCP integrations for Google services (Gmail, Calendar, Drive). No local MCP server needed for Gmail. You authenticate once through the Claude AI OAuth flow and the tools become available in every session.

**Available Gmail tools:**

| Tool | Purpose |
|------|---------|
| `search_threads` | Search Gmail with the same query syntax as the Gmail search bar (`from:`, `subject:`, `is:unread`, `newer_than:`, etc.). Returns thread IDs and snippets, not full bodies. |
| `get_thread` | Fetch a full thread by ID, including all message bodies. Use `messageFormat: "FULL_CONTENT"` to get the actual email text. |
| `create_draft` | Create a draft in Gmail. Accepts `to`, `cc`, `bcc`, `subject`, `body`, and `htmlBody`. Returns the draft ID. |
| `list_drafts` | List existing drafts. |
| `list_labels` / `label_message` / `label_thread` | Label management. |

**Key details:**
- `search_threads` returns snippets only. You must call `get_thread` with the thread ID to read the full email content.
- `create_draft` does NOT send the email. It creates a draft the user reviews and sends manually.
- The `to` field requires plain email addresses (`user@example.com`), not `"Name <user@example.com>"` format.

### 2. Voice Style Guide

Before drafting anything on my behalf, the agent reads a written voice style guide. This is critical: without it, AI-generated emails sound generically professional and nothing like how I actually write.

**What the guide contains:**
- **Core voice description**: warm, direct, enthusiastic. Writes like talking to you.
- **Signature mannerisms**: old-school emoticons (`:)` `:D` `:P`), extended vowels ("Hiiiiii!"), tildes, parenthetical asides.
- **Sentence-level patterns**: flowing/conversational, contractions by default, natural hedging.
- **Tone calibration by context**: personal email vs. professional follow-up vs. role pitch vs. LinkedIn post. Each has different levels of formality, but warmth is always constant.
- **Formality spectrum table**: maps context to specific mannerism usage (emoticons yes/no, extended vowels yes/no, etc.).
- **Anti-patterns**: what AI tends to get wrong (too many sentence fragments, removing emoticons, em dashes, over-formalizing, making emails too long).

**How to build your own:**
1. Collect 20+ real writing samples from before you started using AI (2023 and earlier is safest). Include: personal emails, professional emails, networking messages, blog posts, social media, any longer-form writing.
2. Have Claude analyze the samples for patterns: sentence structure, word choice, punctuation habits, opener/closer patterns, formality variation by context.
3. Validate the guide with an A/B test: generate sample emails with and without the guide, see which ones you'd actually send.
4. Store the guide in a file the agent can read at the start of drafting sessions.

**Where I store mine:**
- Full guide: a dedicated file in my tasks repo (version-controlled, built from pre-AI writing samples only)
- Synopsis in agent guidance: `guidance/written-voice.md` (loaded on-demand by agents)
- Memory pointer: a memory file that tells the agent "read the guide BEFORE drafting, not after"

The memory pointer is important. Without it, the agent will draft first and then check the guide (or not check it at all).

### 3. Agent Instruction System

The agent has layered instructions that shape behavior:

```
1. agent.md          -- global rules (loaded every session)
2. guidance/*.md     -- deep-dive procedures (loaded on-demand)
3. Per-repo CLAUDE.md -- repo-specific rules
4. Memory files      -- cross-session recall (corrections, preferences)
```

For email drafting, the relevant pieces are:
- `guidance/written-voice.md` loaded when drafting
- `guidance/mcp-tools.md` loaded for MCP tool selection rules
- Memory file with "always read voice guide before drafting" instruction
- Memory file with any corrections from past drafting sessions (e.g., "em dashes are an AI tell, don't use them")

### 4. Discord Bot (optional, for hands-free dispatch)

My Discord bot watches a `#requests` channel. When I post a message like "Draft a reply to the Garmin email about the privacy policy", the bot:

1. Classifies the request
2. Spawns a Claude Code CLI session on my local machine (via SSH tunnel from the VM)
3. The agent reads the email, reads the voice guide, and drafts the reply
4. Reports completion back to Discord

This is optional. The same workflow works from a terminal session.

### 5. Supplementary: IMAP Poll Script

For automated workflows that need to find a specific email (e.g., extracting a 2FA code or confirmation link), I have a standalone bash script that:
- Connects to Gmail via IMAP with an app password
- Searches by `--from`, `--subject`, `--newer`
- Can extract URLs from HTML email bodies
- Can poll repeatedly until a match arrives

This is separate from the MCP tools and used for programmatic email reading in scripts, not for drafting.

---

## Typical Workflow: Drafting a Reply

Here's what happens step by step when I ask "Draft a reply to the Garmin email about the privacy policy":

### Step 1: Find the email
```
Agent calls: search_threads(query: "from:garmin subject:privacy policy")
Returns: thread IDs + snippets
```

### Step 2: Read the full thread
```
Agent calls: get_thread(threadId: "<thread_id>", messageFormat: "FULL_CONTENT")
Returns: all messages in the thread with full bodies
```

### Step 3: Read the voice style guide
The agent reads the voice guide to calibrate tone and mannerisms for the context. It checks the formality spectrum table to determine the right register (professional follow-up in this case).

### Step 4: Draft the reply
The agent writes the reply text, matching my voice patterns. For a professional email this means: warm but no emoticons, short (2-4 sentences for simple replies), gets to the point, uses contractions, no em dashes.

### Step 5: Create the draft
Two options depending on the situation:

**Option A: Gmail draft (most common)**
```
Agent calls: create_draft(
  to: ["recipient@example.com"],
  subject: "Re: Privacy Policy Update",
  body: "Hey Marc! ..."
)
Returns: draft ID
```

**Option B: File in repo (for complex/long drafts)**
The agent writes the draft to a markdown file in the relevant repo, commits, and pushes. I then copy-paste from the file into the email. This is useful when:
- The draft is long and needs iteration
- I want version control on the drafting process
- The reply involves significant research that should be preserved alongside the draft

### Step 6: User review
I open Gmail, find the draft, review it, make any tweaks, and hit send. The agent never sends email directly.

---

## Implementation Guide

### Minimum viable setup

1. **Claude Code CLI** with a Claude Max subscription (or API access). The Gmail MCP tools are built into Claude Code, no extra configuration needed.

2. **Voice style guide** stored as a markdown file. Have Claude analyze your real writing samples and produce a guide. Store it somewhere the agent can read it.

3. **Memory/instruction file** that tells the agent "read the voice guide before drafting." Without this, the agent will forget to consult the guide and produce generic output.

That's it for the basics. You can draft email replies from the CLI immediately.

### Adding Discord dispatch (optional)

If you want hands-free dispatch from Discord:

1. **Discord bot** that watches a channel for messages and spawns Claude Code CLI sessions.
2. **SSH tunnel** (if the bot runs on a remote server but Claude Code runs locally) so the bot can invoke the CLI on your local machine.
3. **Interactive session support**: the agent can output `[WAITING_FOR_INPUT]` if it needs clarification, and the bot parks the session and waits for your reply in the Discord thread.

### Key design decisions

| Decision | My choice | Why |
|----------|-----------|-----|
| Draft vs. send | Draft only | Always review before sending. The agent never sends directly. |
| Gmail MCP vs. IMAP | MCP for drafting, IMAP for scripted polling | MCP is simpler and built-in. IMAP is for automated workflows (2FA codes, confirmation links). |
| Voice guide location | Repo file + memory pointer | The guide is version-controlled and the memory tells the agent to read it first. |
| Complex drafts | File in repo | Long drafts or ones that need iteration go to a `.md` file, not directly to Gmail drafts. |
| Email context | `get_thread` for full history | Always read the full thread before drafting, not just the latest message. |

### What to watch out for

1. **Voice drift**: without the style guide, the agent produces increasingly generic professional-sounding emails. Correct early and update the guide.
2. **Thread context**: always have the agent read the full email thread (`get_thread` with `FULL_CONTENT`), not just search snippets. The reply needs to reference the actual conversation.
3. **Draft, never send**: there's no "send" tool in the Gmail MCP. This is by design. Always review.
4. **Email format**: `create_draft` accepts `body` (plain text) and `htmlBody`. For most replies, plain text is fine.
5. **Recipient format**: the `to` field only accepts `user@example.com`, not `"Display Name <user@example.com>"`.
6. **Read before draft**: the most common failure mode is the agent drafting without reading the voice guide. The memory pointer fixes this, but verify it's working in your first few sessions.

---

## Summary

The system is simpler than it looks: Claude Code's built-in Gmail MCP tools handle reading and drafting, a voice style guide ensures the output sounds like me, and the agent never sends anything directly. The Discord bot just provides a convenient way to trigger the workflow without opening a terminal. The hardest part is building a good voice style guide from real pre-AI writing samples.
