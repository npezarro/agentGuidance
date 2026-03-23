# Multi-Session Continuity

For detailed guidance on session ephemerality, crash recovery, and output design, see `guidance/session-lifecycle.md`.

## Picking Up Work from a Previous Session

When continuing work from a previous session (yours or another agent's):

1. **Read `context.md` first.** It's the handoff document.
2. **Check git log.** `git log --oneline -10` to understand recent changes.
3. **Check git status.** Look for uncommitted work left behind.
4. **Check for open PRs.** `gh pr list` to avoid duplicating existing work.
5. **Verify the environment.** Are dependencies installed? Is the build working? Are services running?
6. **Update `context.md` when you're done.** The next session depends on it.

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
