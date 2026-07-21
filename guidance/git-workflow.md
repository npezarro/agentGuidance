<!-- Load when: branching, PRs, merge procedures, commit messages -->
# Git Workflow

## Branch Rules
- Never commit directly to `main`.
- Use the branch assigned to you. If none exists, create one: `agent/<task-name>` or `claude/<task-name>`.
- **Avoid `test-` as a branch prefix.** Some repos have GitHub rulesets or branch protection that silently reject pushes to `test-*` branches (no error, branch just doesn't appear on remote). Use descriptive names like `add-tests-<module>` or `<module>-tests-<run>` instead.
- Commit messages explain **why**, not just what. Large commits are fine; don't split work artificially.
- Before committing:
  1. `git status` to verify no unintended files staged.
  2. `git diff` to review the actual changes.
  3. Confirm no `.env`, secrets, or key files are included.
  4. **Update `context.md`**, mandatory on the final commit of a branch (before creating a PR) or during Session Wrap-Up. Not required on every intermediate commit. See `guidance/context-progress.md`.
  5. **Update `progress.md`**: add an entry for the work being committed. See `guidance/context-progress.md`.
- Push: `git push -u origin HEAD`. Retry network failures up to 4x with backoff (2s, 4s, 8s, 16s). Do not retry auth failures.

## All Deliverables Go in Repos
When creating scripts, tools, project assets, analysis docs, reference files, or any other output, **ALWAYS put them in a git repo under `~/repos/`** and push to GitHub. Never leave files as loose filesystem artifacts — the user doesn't want to dig around the filesystem for deliverables. GitHub is the source of truth. If a new project or tool set doesn't have a repo yet, create one with `gh repo create`.

**This is the most common mistake.** Sessions routinely create useful files (summaries, configs, scripts, reference docs) and then either forget to commit, forget to push, or save them outside a repo. The user cannot access local-only files between sessions. Treat every `Write` or `Edit` call as incomplete until the file is committed and pushed.

## Every Repo Gets a README and Description
Every repo under `~/repos/` must have a `README.md` and a GitHub repo description. When creating a new repo or working in one that's missing either, add them.

- **README.md**: What it does (1-2 sentences), how to set it up, and how to run/use it. Keep it concise -- a developer should understand the project in 60 seconds.
- **GitHub description**: Set via `gh repo edit <owner>/<repo> --description "one-line summary"`. Should be a single sentence that appears on the repo page and in search results.

Both are required when running `gh repo create`. Use `--description` flag on creation. Add the README as part of the initial commit.

## Always Commit and Push Written Files
When creating or modifying files in any repo (via Write, Edit, or any other method), **ALWAYS commit and push in the same step**. Don't move on to other work with untracked or uncommitted files sitting in a repo. The Write tool doesn't commit — you must do it explicitly.

When committing to any repo, **ALWAYS push to the GitHub remote branch as well**. Never leave commits unpushed. Unpushed commits are invisible to other sessions, collaborators, and the deploy pipeline. Treat file creation + `git commit` + `git push` as a single atomic operation — if any step fails, diagnose and fix it before moving on.

**Common gap:** When working across multiple repos in one session (e.g., agentGuidance + llm-tasks + voice-data), it's easy to push some and forget others. After finishing a multi-repo task, verify all repos are clean: `git status` in each one.

## Staging Hygiene in Shared Repos (concurrent agents)

Repos like agentGuidance, privateContext, and knowledgeBase are worked by many agents at once (interactive sessions, hourly learning-agent, doc-sync, autonomousDev). Two rules prevent one agent's commit from corrupting another's work or leaking secrets:

- **Stage explicit paths, never `git add -A` / `git add .`** in a shared repo. A blanket add sweeps whatever another agent left uncommitted in the working tree into *your* commit. This actually happened 2026-07-12: a concurrent session's `git add -A` bundled an unrelated agent's `testing.md` with its own change (and staged a secret — see below). Name the files you touched: `git add guidance/foo.md scripts/bar.sh`.
- **Never `--no-verify` on a public repo.** The pre-commit sensitive-identifier scanner is the last line of defense before a VM username / internal path / token reaches a public GitHub repo. Bypassing it is how leaks ship. If the scanner blocks you, sanitize using `privateContext/sensitive-identifiers.md`; don't override. (The scanner correctly blocked the 2026-07-12 leak — the proper fix went out sanitized via a PR; the `--no-verify` local commit was orphaned.)
- **Before committing, `git status` and confirm ONLY your files are staged.** If you see files you didn't touch, unstage them (`git restore --staged <path>`) — they belong to another agent.

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

## GitHub API PR Creation: Qualify the Head Parameter

When creating PRs via the GitHub REST API (Octokit) rather than `gh pr create`, the `head` parameter must be fully qualified as `owner:branch`, not just `branch`.

```js
// WRONG — causes "invalid head" errors, especially on newly-pushed branches
await octokit.rest.pulls.create({ head: branch, ... });

// CORRECT — qualify with the repo owner
await octokit.rest.pulls.create({ head: `${owner}:${branch}`, ... });
```

**Why:** GitHub needs a few seconds to fully index a newly-pushed branch. Unqualified branch names fail more often during this window. Qualifying with the owner disambiguates the ref lookup and makes the API more reliable.

**Also:** Add a 3s delay before calling `pulls.create` after a push event — GitHub's internal indexing isn't instant. Increase `maxAttempts` to 5 and retry on "invalid head" errors.

**Note:** The `gh pr create` CLI handles head qualification internally. This only applies when using the REST API directly (e.g., in automated bots like claude-auto-merger). Source: auto-merger "invalid head" race condition fix (2026-05-15).

## Branch Hygiene

Open PRs that sit unmerged cause cascading merge conflicts across all other branches. **This is the #1 cause of stuck work.** Prevent this:

- **Merge PRs promptly.** When a PR is ready and has no review requirements, merge it in the same session you created it. Use `gh pr merge <number> --merge --delete-branch`. If the merge fails (merge conflict, checks pending), retry once after 5s. If it still fails, report the specific error.
- **Rebase before opening a PR.** Run `git fetch origin && git rebase origin/main` and resolve any conflicts before pushing. A PR should be mergeable at the time it is created.
- **One branch per task.** Don't create multiple branches for the same feature or leave abandoned branches behind.
- **Clean up stale branches.** At session start, check `gh pr list --state open` and `git branch -a`. If a branch has been open for more than a few days without activity, either rebase and merge it or close it.
- **Don't leave PRs for someone else to merge** unless the task explicitly requires review. Unmerged PRs are invisible debt that compounds with every new branch.
- **Never modify `context.md` or `progress.md` on a branch that other branches also modify.** These files conflict constantly. If you must update them, do it as the very last commit before merging, after rebasing on main. The auto-merger can resolve context.md/progress.md conflicts locally, but code conflicts in these files alongside real code conflicts will block the merge entirely.
- **If a merge fails with code conflicts:** close the PR, delete the branch, and redo the work on a fresh branch from main. Don't waste time resolving complex merge conflicts on stale branches.

### autonomousDev must self-verify its own PRs actually merged (2026-07-05)
fix-checker runs 600-601: three separate autonomousDev-created `claude/auto-*` PRs across different repos (valueSortify #148, runeval #267, and one other) sat MERGEABLE + CI SUCCESS for 2-4 days before fix-checker caught and merged them. Each was a genuine, already-verified fix — the PR just never got merged after creation. Root cause: autonomousDev's closeout logs "PR: <link>" but doesn't check `gh pr view <n> --json state` before ending the session, so a merge step that silently didn't fire (or was never attempted) goes unnoticed until the next fix-checker pass. **Fix:** autonomousDev should re-check `gh pr view --json state,mergeable` for the PR it just created as the last step of its own session, and merge it right then if MERGEABLE + CI SUCCESS, instead of relying on fix-checker as a merge backstop.

### `git push` blocked by missing `workflow` OAuth scope when the branch carries a `.github/workflows/*` edit (recurring since 2026-04, fixed 2026-07-21)
The `gho_` OAuth token used by `git`/`gh` in autonomousDev-style automated sessions lacks the `workflow` scope, so any push where the branch's diff touches `.github/workflows/*.yml` is rejected: `refusing to allow an OAuth App to create or update workflow ... without workflow scope`. This has recurred across at least 5 repos over several months (deal-scout, aisleOffersFilterClaimandTracking, auto-shorts-worker, browser-agent, phone-agent run #337) — prior fixes worked around it per-incident (switch to an SSH remote, or create the branch/PR via the GitHub API instead of `git push`), which is more setup than needed.

**Preferred fix:** the workflow-file edit is usually not yours — it's an unpushed dependabot/CI-config commit already sitting on the local default branch (itself failed to push for the same reason), and your feature branch inherited it by branching off local, not remote. Strip it out by rebasing onto the remote base instead of local:
```bash
git fetch origin <default-branch>
git rebase --onto origin/<default-branch> <default-branch> <your-branch>
git diff --stat origin/<default-branch>..HEAD   # should show only your files, no .github/
git push
```
**Detect early**, before attempting the push: `git log --oneline origin/<default-branch>..HEAD` on your branch — if a commit there touches `.github/workflows/`, it's not yours to push and the rebase above is needed. If your task genuinely does need to modify a workflow file, this rebase won't help — fall back to SSH push or an API-created PR as before.

### Merged-PR scope notes are sanctioned follow-up work, not dedup blockers (2026-07-03)
autonomous-dev run 325: When candidate work looks like a duplicate of a recently MERGED PR, read the merged PR's body before rejecting it. An explicit 'out of scope / flagged as a follow-up' note converts the candidate from forbidden duplicate into sanctioned, pre-vetted follow-up work — and the merged PR often ships infrastructure the follow-up should reuse instead of re-inventing (health-hub PR #66 scope note + safeJsonParse helper -> PR #67 per-event webhook batch isolation). Cite the scope note in the new PR body to make the lineage reviewable.

### After a direct-commit branch merges, restore the shared checkout to main (2026-07-15)
learning-agent run #945: found `~/repos/agentGuidance`'s shared main checkout still on `claude/essential-rule1-paste-output-1784121274` — a branch a prior session committed directly to (not via worktree) that had already merged (PR #327) hours earlier. Content was identical to `origin/main` (safe, no data loss), but until caught, every SessionStart/hook read in that repo for any concurrent session was resolving against the stale feature branch instead of main. Root cause: a session that commits directly on the shared checkout (skipping the worktree pattern this file's "Staging Hygiene" section mandates) has no natural trigger to `git checkout main && git pull` after its PR merges — nothing forces it back. **Fix:** any session that commits directly on a shared repo's main checkout (rather than a worktree) must `git checkout main && git pull origin main` as its last step once the PR is confirmed merged. Prefer the worktree pattern entirely to avoid this class of bug — it never leaves the shared checkout on a non-main branch in the first place.
