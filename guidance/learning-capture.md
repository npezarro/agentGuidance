# Learning Capture

Operational learnings, behavioral adjustments, and discovered patterns must be captured **immediately when they occur**, not deferred to session wrapup.

## The Three-Destination Rule

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

### Step 1: Save to memory (always)
Standard memory file with frontmatter.

### Step 2: Identify the right repo-level destination(s)

| Learning Type | Repo Destination | agentGuidance/privateContext? |
|---|---|---|
| Repo-specific rule | That repo's `CLAUDE.md` | Only if it's a cross-project pattern |
| Workflow pattern | N/A | `agentGuidance/guidance/<topic>.md` |
| Prompt template | N/A | `privateContext/prompts/<name>.md` |
| Infrastructure detail | N/A | `privateContext/infrastructure.md` or `accounts.md` |
| Agent profile learning | N/A | `agentGuidance/profiles/<agent>/experience.md` |
| User preference/style | N/A | `agentGuidance/guidance/written-voice.md` or similar |

### Step 3: Commit and push
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

## What NOT to Capture

- One-time debugging steps (they're in git history)
- Code patterns visible from reading the code
- Task-specific context that won't recur
- Anything already documented in the destination file
