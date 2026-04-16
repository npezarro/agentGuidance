# Learning Capture

Operational learnings, behavioral adjustments, and discovered patterns must be captured **immediately when they occur**, not deferred to session wrapup.

## The Multi-Destination Rule

Every learning has up to four destinations. Always evaluate which apply:

| Destination | What Goes Here | Who Benefits |
|---|---|---|
| **Memory** (`~/.claude/projects/.../memory/`) | Personal cross-session recall | This user's future Claude sessions |
| **Project repo** (`CLAUDE.md`, `context.md`) | Repo-specific rules and patterns | Any agent working in that specific repo |
| **agentGuidance or privateContext** | Cross-project patterns and operational knowledge | All agents, all repos, all sessions |
| **knowledgeBase** (`~/repos/knowledgeBase/`) | Cross-repo synthesized knowledge (when a learning spans 3+ repos) | Any agent needing cross-cutting context |

### Decision: agentGuidance vs privateContext

- **agentGuidance** (public): Behavioral rules, workflow patterns, techniques, prompt strategies, integration patterns. Nothing that reveals infrastructure, credentials, or sensitive identifiers.
- **privateContext** (private): Prompt templates with sensitive details, credential patterns, infrastructure-specific knowledge, project-specific operational details that reference internal systems.
- **When in doubt:** If it mentions a hostname, IP, username, API key, or private repo name, it goes in privateContext. See `guidance/secrets-hygiene.md`.

## What Counts as a Learning

- A behavior that should be repeated or avoided in future sessions
- A new capability, tool, or integration pattern that was established
- A correction from the user (explicit or implied)
- A failure mode discovered and its fix
- A prompt strategy or framing that produced better results
- An infrastructure detail that future sessions will need
- An adjustment to an existing rule based on new evidence

## When to Capture

**Immediately**, not at session end. Specifically:

1. **User corrects you** — Save the feedback before continuing with the corrected approach
2. **New capability established** — After verifying it works, record it before moving on
3. **Pattern discovered** — After confirming the pattern, persist it
4. **Integration wired up** — After testing, document the wiring

Do NOT batch these to session wrapup. By then, details are lost and the learning is less precise.

## How to Capture

### Preferred: Use the Propagation Script

The fastest and most reliable way to capture a learning is the single-command propagation script:

```bash
~/repos/agentGuidance/scripts/propagate-learning.sh \
  --type feedback \
  --summary "One-line description" \
  --body "Full learning content" \
  --repo <repo-name> \
  --guidance-file guidance/<relevant-file>.md
```

This handles memory + CLAUDE.md + guidance file in one command. Add `--private` for privateContext routing, `--cross-cutting` for knowledgeBase flagging, `--dry-run` to preview.

For complex or nuanced learnings where the script isn't sufficient, you can also spawn the **propagation agent** (`~/.claude/agents/propagation.md`) which handles routing decisions, duplicate checking, and MANIFEST.md lookup.

### Manual Capture (when the script doesn't fit)

#### Step 1: Save to memory (always)
Standard memory file with frontmatter.

#### Step 2: Identify the right repo-level destination(s)

| Learning Type | Repo Destination | agentGuidance/privateContext? |
|---|---|---|
| Repo-specific rule | That repo's `CLAUDE.md` | Only if it's a cross-project pattern |
| Workflow pattern | N/A | `agentGuidance/guidance/<topic>.md` |
| Prompt template | N/A | `privateContext/prompts/<name>.md` |
| Infrastructure detail | N/A | `privateContext/infrastructure.md` or `accounts.md` |
| Agent profile learning | N/A | `agentGuidance/profiles/<agent>/experience.md` |
| User preference/style | N/A | `agentGuidance/guidance/written-voice.md` or similar |

#### Step 3: Commit and push
Learnings committed to agentGuidance or privateContext must be pushed immediately. They're useless if they sit local-only.

## Updating Existing Guidance

When a learning modifies or extends an existing rule:
1. **Find the canonical source** in `MANIFEST.md`
2. **Edit in place** — Don't create a new file if an existing one covers the topic
3. **Update MANIFEST.md** if you add a new guidance file
4. **Update agent.md's Guidance File Index** if you add a new guidance file

## Responding to Mistakes

When you make a mistake and identify the cause, run this process before moving on:

1. **Check existing guidance.** Search `agentGuidance/guidance/` and `privateContext` for rules that should have prevented the mistake.
2. **If the rule exists:** Figure out why it wasn't followed. Is the rule too narrow? Was there a gap in the trigger condition? Update the rule to close the gap.
3. **If no rule exists:** Add one to the appropriate location (agentGuidance for cross-session, repo CLAUDE.md for repo-specific).
4. **Commit and push the rule update** — rules that aren't pushed don't help future sessions.

**Why this matters:** Rules that exist but aren't followed indicate either a rule clarity problem or a missing trigger condition. Every failure should become a rule improvement — don't just fix the symptom, patch the prevention.

## Explicit User Directives ("Update Guidance", "Record This")

When the user says **"update guidance"**, **"record this into guidance"**, **"save this direction"**, or similar — the primary target is **always repo instruction files**, not memory.

### Routing Order for User Directives

1. **Find the canonical source** — Check `MANIFEST.md` for the right file. If the directive maps to an existing guidance file, edit it in place.
2. **Update the repo file(s)** — Edit the relevant file in `agentGuidance/guidance/`, `privateContext/`, the project's `CLAUDE.md`, or `autonomousDev-private/` as appropriate.
3. **Update the wiki** — If the change affects cross-repo knowledge (instruction architecture, integration patterns, or anything already covered by a knowledgeBase article), update the relevant wiki page too.
4. **Commit and push** — Immediately. Unpushed rule changes don't help future sessions.
5. **Optionally save a memory file** — As a personal index/cache. Memory is supplementary, never the primary destination.

### Common Mistakes to Avoid

- **Memory-only updates**: Writing a memory file and stopping. Memory is invisible to other agents and sessions that don't share your memory directory. The user said "update guidance" — they mean the durable instruction system.
- **Skipping the wiki**: If the topic already has a knowledgeBase article (check `~/repos/knowledgeBase/` first), update it alongside the guidance file.
- **Creating new files when an existing one covers the topic**: Always check MANIFEST.md and search guidance/ first.

### Trigger Keywords

React to any of these as a directive to update repo files:
- "update guidance" / "add to guidance" / "record this into guidance"
- "save this direction" / "save this rule"
- "remember this for all sessions" / "make this permanent"
- "add this to the rules" / "update the rules"
- Any correction + "make sure this doesn't happen again"

## What NOT to Capture

- One-time debugging steps (they're in git history)
- Code patterns visible from reading the code
- Task-specific context that won't recur
- Anything already documented in the destination file
