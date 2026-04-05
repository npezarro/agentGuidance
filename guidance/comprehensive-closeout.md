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

## Relationship to Standard Wrapup

Comprehensive closeout **replaces** steps 7-9 of `session-wrapup.md` (Discord post, reference links, file links) with its own richer versions. Steps 1-6 and 10-11 still apply (review, context.md, progress.md, commit, push, verify, completed-work.md, learnings).

## Tips

- Write the document first, then derive the Discord/WordPress posts from it
- The document is the source of truth; Discord and WordPress are distribution
- Be generous with detail in the Decisions section — that's what future sessions will need most
- Include the user's exact words when they defined requirements or made choices
