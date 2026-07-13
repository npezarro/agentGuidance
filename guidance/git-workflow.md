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
- **Prune remote-tracking refs before scanning.** Before enumerating branches with `git branch -a` or `git branch -r`, run `git remote prune origin` (and any other remotes). Without pruning, remote-tracking refs for branches deleted from GitHub remain locally and inflate "open branch" counts in automated scanners. Source: autonomousDev run #305 (2026-06-11) — 6 of 12 "open branches" were phantom stale refs from a prior cleanup that hadn't been pruned.
- **Automation cap/dedup gates MUST use `git ls-remote`, not `git branch -r`.** `git branch -r` reads local remote-tracking refs that are only refreshed on `git fetch --prune` — pruning in the same script helps but is still racy if another process deleted the branch between runs. For cap checks, backlog gates, and any automation that needs to know which branches *currently* exist on the remote, query the remote directly: `git ls-remote --heads origin 'claude/auto-*'`. This is always authoritative. Source: autonomousDev-private dedup.sh — runs 318–320 all triggered BACKLOG CLEANUP MODE on 0 real open branches because stale tracking refs for already-merged `claude/auto-*` branches lingered (fixed PR #30, 2026-06-27).
- **Don't leave PRs for someone else to merge** unless the task explicitly requires review. Unmerged PRs are invisible debt that compounds with every new branch.
- **Never modify `context.md` or `progress.md` on a branch that other branches also modify.** These files conflict constantly. If you must update them, do it as the very last commit before merging, after rebasing on main. The auto-merger can resolve context.md/progress.md conflicts locally, but code conflicts in these files alongside real code conflicts will block the merge entirely.
- **If a merge fails with code conflicts:** close the PR, delete the branch, and redo the work on a fresh branch from main. Don't waste time resolving complex merge conflicts on stale branches.
- **MERGEABLE ≠ non-redundant.** A `claude/auto-*` feature PR can show MERGEABLE yet have its entire patch already on `main` — this happens when a doc-sync or doc-update PR branched off the feature branch and carried the code into main via its own merged PR. Before merging any feature PR that looks "ready," run `git rebase origin/main` in a throwaway checkout: if the commit is silently dropped ("patch contents already upstream") or `git diff origin/main <tip>` is empty, the content already landed. Close the original feature PR as superseded (`gh pr close <N> --delete-branch --comment "Superseded by ..."`) rather than producing a duplicate merge. Source: run #319 (2026-06-26) — valueSortify PR #145 was MERGEABLE but fully contained in doc-sync PR #146, which had already merged.

### claude-auto-merger self-merges EVERY non-draft PR from ANY pushed branch by default (2026-07-04)

The auto-merger's default is opt-out, not opt-in: any PR it creates from a pushed branch (including one-off human/design branches never meant to reach `main`) gets merged within seconds, with no review checkmark step. Pushing a branch you don't want merged yet is not safe by default — you must actively block it. **Immediate mitigation:** convert the PR to draft right after pushing (`gh pr ready <n> --undo`); draft PRs are never auto-merged. **Durable fix (now live):** the auto-merger supports a repo-level `EXCLUDED_REPOS` denylist — repos on it no longer auto-merge on push or PR events, while still auto-merging recognized safe lanes (doc-sync, claudemd-audit, daily-tldr, gemini-fix, crash-fix branch prefixes). Per-commit override in the head commit message: `[automerge]` forces a merge even on an excluded repo; `[no-automerge]`/`[skip-am]` suppresses merging anywhere. Add any new product/design repo (one with real human or design branches, as opposed to a tooling repo relying on blind auto-merge for its own `feat/*`/`fix/*` branches) to the denylist before its first non-lane push, not after. Source: netflix-social-platform incident where pushed design branches were merged+reverted twice before the denylist landed.

## Staging Changes in Hook-Executing Repos: Use Worktrees, Not Branch Checkouts

**Never run `git checkout <branch>` in the main checkout of a repo whose working copy is referenced by live hooks or SessionStart scripts** (e.g., `~/repos/agentGuidance`, `~/repos/autonomousDev-private`). The session harness executes directly from these working-copy paths. Switching their branch silently reverts all guidance, hooks, and config to whatever the target branch holds — new rules vanish, graduated rules reappear, hooks change behavior — for every concurrent session and every agent that runs during or after the switch.

**The safe pattern:** use a git worktree instead.

```bash
# Stage changes for review without touching the main checkout
git -C ~/repos/<repo> worktree add /tmp/learnings-wt-<repo> -b claude/learnings-<run>
# ... make edits, commit, push, open PR from inside /tmp/learnings-wt-<repo> ...
git -C ~/repos/<repo> worktree remove /tmp/learnings-wt-<repo>
# Main checkout stays on main throughout; hooks keep running from live state
```

**Real incident (2026-06-10, e721c06):** the learning agent checked out its staging branch inside `~/repos/agentGuidance`. The ESSENTIAL.md rules reverted to the pre-section-7 version (16 rules), new hooks disappeared, and the live harness ran in the wrong state for the duration of the session. All of this was silent — no error, no warning.

**Repos requiring worktrees:** any repo where `~/repos/<repo>/` appears in a hook path, SessionStart hook, or PM2 config that loads guidance at runtime.

### autonomousDev must self-verify its own PRs actually merged (2026-07-05)
fix-checker runs 600-601: three separate autonomousDev-created `claude/auto-*` PRs across different repos (valueSortify #148, runeval #267, and one other) sat MERGEABLE + CI SUCCESS for 2-4 days before fix-checker caught and merged them. Each was a genuine, already-verified fix — the PR just never got merged after creation. Root cause: autonomousDev's closeout logs "PR: <link>" but doesn't check `gh pr view <n> --json state` before ending the session, so a merge step that silently didn't fire (or was never attempted) goes unnoticed until the next fix-checker pass. **Fix:** autonomousDev should re-check `gh pr view --json state,mergeable` for the PR it just created as the last step of its own session, and merge it right then if MERGEABLE + CI SUCCESS, instead of relying on fix-checker as a merge backstop.

### Merged-PR scope notes are sanctioned follow-up work, not dedup blockers (2026-07-03)
autonomous-dev run 325: When candidate work looks like a duplicate of a recently MERGED PR, read the merged PR's body before rejecting it. An explicit 'out of scope / flagged as a follow-up' note converts the candidate from forbidden duplicate into sanctioned, pre-vetted follow-up work — and the merged PR often ships infrastructure the follow-up should reuse instead of re-inventing (health-hub PR #66 scope note + safeJsonParse helper -> PR #67 per-event webhook batch isolation). Cite the scope note in the new PR body to make the lineage reviewable.
