# Multi-Session Continuity

For detailed guidance on session ephemerality, crash recovery, and output design, see `guidance/session-lifecycle.md`.

## Picking Up Work from a Previous Session

When continuing work from a previous session (yours or another agent's), check available context before diving in. The goal is to avoid re-discovering what a prior session already figured out.

### Context sources (check in order)

1. **Read `context.md` first.** It's the handoff document — current state, blockers, next steps.
2. **Read the repo's `CLAUDE.md`.** It has architecture, operational rules, and gotchas specific to this project.
3. **Check memory.** Your memory system may have relevant project, feedback, or reference entries from prior conversations.
4. **Check git log.** `git log --oneline -10` to understand recent changes and commit messages.
5. **Check git status.** Look for uncommitted work left behind.
6. **Check for open PRs.** `gh pr list` to avoid duplicating existing work.
7. **Check closeout reports.** Recent closeouts in Discord #closeout or on the blog (search WordPress posts via `search-wp-posts.sh`) often have detailed context on what was done, decisions made, and what's left.
8. **Check the agent journal.** The startup hook shows recent journal entries — scan for relevant discoveries or blockers.
9. **Verify the environment.** Are dependencies installed? Is the build working? Are services running?

### Why this matters

Every new session starts from zero. Without checking these sources, you will repeat investigations, miss decisions already made, or contradict prior work. Five minutes of context-gathering saves thirty minutes of re-discovery.

### When you're done

10. **Update `context.md`.** The next session depends on it.
11. **Persist learnings.** If you discovered something that isn't in the repo's CLAUDE.md or memory, add it so the next session doesn't have to re-learn it.

## Mid-Session Instruction Refresh (`--refresh`)

When the owner types `--refresh`, re-read the latest instructions without restarting the session. This preserves conversation context while picking up changes to agent.md, guidance files, or CLAUDE.md.

**When you see `--refresh`:**
1. Run the refetch script and read its output:
   ```bash
   bash ~/repos/agentGuidance/scripts/refetch-instructions.sh
   ```
   For a deeper refresh that includes all guidance files:
   ```bash
   bash ~/repos/agentGuidance/scripts/refetch-instructions.sh --with-guidance
   ```
2. Also re-read the current repo's `CLAUDE.md` if one exists (it may have changed).
3. Confirm what was refreshed:
   > **Instructions refreshed.** Re-read agent.md (v[version if visible]), [N] guidance files, and local CLAUDE.md. Changes noted: [brief summary of anything visibly different, or "no visible changes"].
4. Apply the updated instructions for the remainder of the session.

**When to suggest `--refresh`:**
- If the owner mentions they've updated agent.md, CLAUDE.md, or any guidance files during this session
- If you notice your behavior contradicts what the owner is describing as the expected behavior
- After the owner merges a PR that modifies agentGuidance
