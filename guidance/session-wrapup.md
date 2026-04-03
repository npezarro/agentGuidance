# Session Wrap-Up

For the reasoning behind these requirements, see `guidance/session-lifecycle.md` and `guidance/process-hygiene.md`.

**Before ending any session where you wrote or changed code, you MUST complete all of these steps.** Do not wait to be asked; this is automatic.

1. **Review what's left.** Before doing anything mechanical, stop and think through:
   - Did the user's request get fully addressed, or is something partially done?
   - Are there obvious next steps the user would want to know about (e.g., "this needs a deploy", "tests should be run against staging", "the other half of the refactor")?
   - Did anything come up during the session that warrants follow-up (broken tests elsewhere, tech debt spotted, a dependency that needs updating)?
   - Were there decisions made that the user should revisit or that future sessions need context on?

   List these out explicitly in the closeout — both in the in-conversation report and in the Discord thread. Don't just say "no open items" reflexively; actually check. If there genuinely are none, that's fine, but the default should be to surface things rather than assume everything is wrapped up.

2. **Update `context.md`**: reflect the current state of the project, what changed, and any open work. (This is the final branch commit, so `context.md` must be updated here.)
3. **Update `progress.md`**: add entries for any work committed this session.
4. **Commit all changes.** Stage relevant files (never `.env`, secrets, or build artifacts). Write a commit message that explains *why*, not just *what*.
5. **Push to remote.** `git push -u origin HEAD`. Confirm the push succeeded.
6. **Verify nothing was left behind.** Run `git status` after pushing. There should be no uncommitted changes related to the task.
7. **Post a work summary to Discord.** Use `~/repos/privateContext/discord-webhook.sh` to post to `#cli-interactions`. **Always use the two-argument form** to create a real Discord thread:
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

8. **Include reference links in Discord messages.** When reporting to `#cli-interactions`, include GitHub links to make it easy to jump to the changes:
   - **Commit links:** `https://github.com/npezarro/<repo>/commit/<hash>` for the key commits
   - **Branch/PR links:** Link to the PR or branch comparison when relevant
   - **Repo link:** At minimum, link to the repo being worked on
   - These go in the thread detail alongside the narrative, not as a separate section. Weave them in naturally (e.g., "Added validation to the API route ([commit](https://github.com/npezarro/repo/commit/abc1234))").

9. **Post file links to `#file-links` when you generate readable artifacts.** Use `~/repos/privateContext/file-links-post.sh` when you create files the user will want to open directly:
   ```bash
   ./file-links-post.sh "Description of file" "https://github.com/npezarro/repo/blob/branch/path/to/file.md"
   ```
   **When to post:**
   - Reports, analyses, or summaries written to `.md` files
   - Application materials (cover letters, resumes) written to files
   - Any file explicitly generated for the user to read

   **When NOT to post:**
   - Bulk code changes across many files (that's what commit links in `#cli-interactions` are for)
   - Config files, test files, or internal tooling changes
   - Files that are part of normal development flow (the user isn't going to read `context.md`)

10. **Update `~/repos/privateContext/completed-work.md`** with what was done this session. This is the cross-session deduplication log. Include learnings and patterns discovered, not just tasks completed.

**Key distinction:** `progress.md` is updated on every commit (append-only, uses `merge=union`). `context.md` is updated only on the final branch commit or at session end (mutable snapshot, can't be auto-merged).

If the build is broken and you cannot fix it before the session ends, still commit and push with a clear note in the commit message and `context.md` explaining the broken state so the next session can pick it up. Uncommitted local changes are invisible to future sessions and effectively lost work.
