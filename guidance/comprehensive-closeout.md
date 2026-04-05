# Comprehensive Closeout

Use when a session involves significant decisions, new systems, architectural changes, or anything worth referencing later. This produces a durable, detailed document beyond the standard session-wrapup.

## When to Use

- User explicitly requests it
- Session established a new system, agent, or workflow
- Session involved architectural decisions with trade-offs
- Session produced learnings that affect multiple repos
- Multi-hour sessions covering complex ground

## What It Produces

### 1. Detailed Markdown Document

Written to `~/repos/privateContext/deliverables/closeouts/YYYY-MM-DD-<slug>.md`.

Structure:

```markdown
# <Session Title>
**Date:** YYYY-MM-DD
**Duration:** approximate
**Repos touched:** list

## Context & Motivation
Why this work was initiated. What problem was being solved.
Include the user's original request and any refinements.

## Decisions Made
For each significant decision:
- **Decision:** What was decided
- **Alternatives considered:** What else was on the table
- **Rationale:** Why this option was chosen
- **Trade-offs:** What was given up

## What Was Built / Changed
Detailed narrative of what happened, in chronological order.
Include file paths, commit hashes, PR links.
Enough detail that someone could understand the full picture
without reading the conversation.

## Architecture & Design
For new systems: how it works, what connects to what,
data flow, scheduling, capacity constraints.
Include diagrams (ASCII) if helpful.

## Learnings Captured
List every learning that was persisted this session,
with where it was saved (memory, guidance, repo CLAUDE.md).

## Open Items & Follow-ups
Anything not yet done, next steps, things to watch for.

## Key Files
Links to the most important files created or modified.
```

### 2. WordPress Post

Post the document to WordPress as a permanent, searchable record. Use the SSH posting method (`~/repos/agentGuidance/hooks/post-to-wordpress.sh` or direct `wp-cli` via SSH).

### 3. Discord Notification

Post to `#cli-interactions` with a link to the WordPress post and a brief summary. This replaces the standard closeout Discord post (don't double-post).

### 4. File Links

Post the GitHub link to the closeout document to `#file-links`.

### 5. Repo Context Updates (Critical for Session Continuity)

The closeout document is the *archive*. The actual handoff mechanism that new sessions read is `context.md` in each touched repo. **This is the step that makes deep closeouts useful to future sessions.**

For every repo touched during the session:

1. **Update `context.md`** with:
   - What changed this session (summary, not full narrative)
   - Key decisions made and their rationale (condensed from the closeout Decisions section)
   - Open items and follow-ups specific to this repo
   - A pointer to the full closeout: `Full session closeout: privateContext/deliverables/closeouts/YYYY-MM-DD-<slug>.md`
   - Current state: what's working, what's broken, what's in-progress

2. **Update `progress.md`** with commit-level entries as usual.

3. If a repo doesn't have `context.md` yet, create one from the `agentGuidance/templates/context.md` template.

**Why this matters:** New sessions load CLAUDE.md, context.md, and progress.md from the repo they're working in. They do NOT automatically read closeout documents in privateContext. Without this step, the deep closeout is a dead letter — rich context that no future session ever sees.

### 6. Memory Update

Update the relevant project memory file in `~/.claude/projects/-mnt-c-Users-npeza/memory/` with:
- Current state of the project after this session
- Pointer to the closeout document for full context
- Any open items that span beyond this single repo

This ensures sessions started from outside the repo (e.g., the home directory) also have access to the handoff context.

## Relationship to Standard Wrapup

Comprehensive closeout **replaces** steps 7-9 of `session-wrapup.md` (Discord post, reference links, file links) with its own richer versions. Steps 1-6 still apply (review, commit, push, verify). Steps 5 and 6 above replace the standard context.md/progress.md updates with richer versions derived from the closeout document.

## Tips

- Write the closeout document first, then derive everything else from it (context.md, Discord, WordPress, memory)
- The closeout document is the archive; `context.md` is the handoff; Discord/WordPress are distribution
- Be generous with detail in the Decisions section — that's what future sessions will need most
- Include the user's exact words when they defined requirements or made choices
- Test the handoff: read each repo's `context.md` after updating it and ask "could a new session pick this up cold?"
