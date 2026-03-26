# Git Workflow

## Branch Rules
- Never commit directly to `main`.
- Use the branch assigned to you. If none exists, create one: `agent/<task-name>` or `claude/<task-name>`.
- Commit messages explain **why**, not just what. Large commits are fine; don't split work artificially.
- Before committing:
  1. `git status` to verify no unintended files staged.
  2. `git diff` to review the actual changes.
  3. Confirm no `.env`, secrets, or key files are included.
  4. **Update `context.md`**, mandatory on the final commit of a branch (before creating a PR) or during Session Wrap-Up. Not required on every intermediate commit. See `guidance/context-progress.md`.
  5. **Update `progress.md`**: add an entry for the work being committed. See `guidance/context-progress.md`.
- Push: `git push -u origin HEAD`. Retry network failures up to 4x with backoff (2s, 4s, 8s, 16s). Do not retry auth failures.

## All Deliverables Go in Repos
When creating scripts, tools, or project assets, **ALWAYS put them in a git repo under `~/repos/`** and push to GitHub. Never leave files as loose filesystem artifacts — the user doesn't want to dig around the filesystem for deliverables. GitHub is the source of truth. If a new project or tool set doesn't have a repo yet, create one with `gh repo create`.

## Always Commit and Push Written Files
When creating or modifying files in any repo (via Write, Edit, or any other method), **ALWAYS commit and push in the same step**. Don't move on to other work with untracked or uncommitted files sitting in a repo. The Write tool doesn't commit — you must do it explicitly.

When committing to any repo, **ALWAYS push to the GitHub remote branch as well**. Never leave commits unpushed. Unpushed commits are invisible to other sessions, collaborators, and the deploy pipeline. Treat file creation + `git commit` + `git push` as a single atomic operation — if any step fails, diagnose and fix it before moving on.

**Common gap:** When working across multiple repos in one session (e.g., agentGuidance + assortedLLMTasks + my-voice), it's easy to push some and forget others. After finishing a multi-repo task, verify all repos are clean: `git status` in each one.

## Creating PRs (with retry)

After `git push`, GitHub may take a few seconds to register the branch. Always verify the branch exists remotely before creating the PR, and retry on failure:

```bash
# 1. Wait for GitHub to register the pushed branch
for i in 1 2 3 4 5; do
  if gh api "repos/{owner}/{repo}/branches/$(git branch --show-current)" --silent 2>/dev/null; then
    break
  fi
  echo "Waiting for GitHub to register branch (attempt $i)..."
  sleep $((i * 2))
done

# 2. Check for existing PR on this branch
EXISTING=$(gh pr list --state all --head "$(git branch --show-current)" --json number --jq '.[0].number')
if [ -n "$EXISTING" ]; then
  echo "PR #$EXISTING already exists for this branch"
  # Update the existing PR if needed, or merge it
else
  # 3. Create the PR with retry
  for i in 1 2 3; do
    if gh pr create --title "<task>" --body "<context>"; then
      break
    fi
    echo "PR creation failed (attempt $i), retrying in $((i * 3))s..."
    sleep $((i * 3))
  done
fi
```

**Never fall back to a "create manually" URL.** If `gh pr create` fails after 3 retries, diagnose the error (auth, branch not found, network) and fix it. Do not tell the user to create the PR manually.

- Do **not** enable auto-merge unless explicitly asked.

## Branch Hygiene

Open PRs that sit unmerged cause cascading merge conflicts across all other branches. **This is the #1 cause of stuck work.** Prevent this:

- **Merge PRs promptly.** When a PR is ready and has no review requirements, merge it in the same session you created it. Use `gh pr merge <number> --merge --delete-branch`. If the merge fails (merge conflict, checks pending), retry once after 5s. If it still fails, report the specific error.
- **Rebase before opening a PR.** Run `git fetch origin && git rebase origin/main` and resolve any conflicts before pushing. A PR should be mergeable at the time it is created.
- **One branch per task.** Don't create multiple branches for the same feature or leave abandoned branches behind.
- **Clean up stale branches.** At session start, check `gh pr list --state open` and `git branch -a`. If a branch has been open for more than a few days without activity, either rebase and merge it or close it.
- **Don't leave PRs for someone else to merge** unless the task explicitly requires review. Unmerged PRs are invisible debt that compounds with every new branch.
- **Never modify `context.md` or `progress.md` on a branch that other branches also modify.** These files conflict constantly. If you must update them, do it as the very last commit before merging, after rebasing on main. The auto-merger can resolve context.md/progress.md conflicts locally, but code conflicts in these files alongside real code conflicts will block the merge entirely.
- **If a merge fails with code conflicts:** close the PR, delete the branch, and redo the work on a fresh branch from main. Don't waste time resolving complex merge conflicts on stale branches.
