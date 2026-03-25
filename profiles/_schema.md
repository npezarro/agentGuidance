# Agent Profile Schema

Persistent agent profiles live in this directory. Each agent gets a subdirectory with two files:

## Directory Structure

```
profiles/
  _schema.md              # this file
  <agent-key>/
    profile.md            # static identity, perspective, working style
    experience.md         # append-only task summaries and learnings
```

## profile.md

Static identity that rarely changes. Sections:

- **Identity** -- name, key, emoji
- **Perspective** -- how this agent thinks and approaches problems
- **Working Style** -- specific behaviors and priorities
- **Expertise** -- domain keywords
- **Deference Rules** -- when to defer to other agents (optional)

## experience.md

Append-only log of task summaries. Each entry is a `---`-separated block:

```markdown
---
## YYYY-MM-DD | <project or context>
**Task:** one-line description
**What worked:** key approach or pattern that succeeded
**What didn't:** missteps, dead ends, or approaches that were abandoned
**Learned:** reusable insight for future tasks
```

## How Profiles Are Used

1. **Discord personas**: `personaProfiles.js` reads profile + tail of experience, injects into the persona prompt
2. **Claude Code agents**: Agent `.md` files reference profile + experience at session start
3. **Autonomous agents**: Read profile + experience as prior context before starting work
4. **Bakeoff testing**: Environments include profile + experience to test impact on output quality

## Experience Entry Guidelines

- Only log substantial work (not quick lookups or one-line answers)
- Focus on transferable learnings, not task-specific details
- Keep entries concise: 4-6 lines per entry
- Be honest about what didn't work -- that's the most valuable signal
