# Session Wrap-Up

For the reasoning behind these requirements, see `guidance/session-lifecycle.md` and `guidance/process-hygiene.md`.

**Before ending any session where you wrote or changed code, you MUST complete all of these steps.** Do not wait to be asked; this is automatic.

1. **Update `context.md`**: reflect the current state of the project, what changed, and any open work. (This is the final branch commit, so `context.md` must be updated here.)
2. **Update `progress.md`**: add entries for any work committed this session.
3. **Commit all changes.** Stage relevant files (never `.env`, secrets, or build artifacts). Write a commit message that explains *why*, not just *what*.
4. **Push to remote.** `git push -u origin HEAD`. Confirm the push succeeded.
5. **Verify nothing was left behind.** Run `git status` after pushing. There should be no uncommitted changes related to the task.
6. **Post a work summary to Discord.** Use `~/repos/privateContext/discord-webhook.sh` to post to `#cli-interactions`. **Always use the two-argument form** to create a real Discord thread:
   ```bash
   ./discord-webhook.sh "top-line summary" "detailed thread body"
   ```
   - **First argument (top-line):** Project name + 2-3 sentence summary of what changed and why.
   - **Second argument (thread detail):** Be **verbose and thorough**. Include:
     - What was done, step by step, with enough narrative for someone outside the session to follow
     - Why each significant choice was made
     - What was tried that didn't work and what was done instead
     - File paths and specific changes for traceability
     - Current state after the session (what's working, what's not)
     - Follow-ups and open items
   - The script handles chunking (splits at 1990 chars). Don't hold back on length.
   - Reply to an existing thread: `./discord-webhook.sh --thread <thread_id> "additional message"`

   **Ongoing reporting during long sessions:**
   Don't wait until session end to report. Post as you complete distinct tasks:
   - **New task = new top-level message.** When switching to a different task, create a fresh message + thread.
   - **Updates within the same task = thread replies.** Use `./discord-webhook.sh --thread <thread_id> "update"`.
   - **Save the thread ID** from the webhook response so you can reply later.

7. **Update `~/repos/privateContext/completed-work.md`** with what was done this session. This is the cross-session deduplication log. Include learnings and patterns discovered, not just tasks completed.

**Key distinction:** `progress.md` is updated on every commit (append-only, uses `merge=union`). `context.md` is updated only on the final branch commit or at session end (mutable snapshot, can't be auto-merged).

If the build is broken and you cannot fix it before the session ends, still commit and push with a clear note in the commit message and `context.md` explaining the broken state so the next session can pick it up. Uncommitted local changes are invisible to future sessions and effectively lost work.
