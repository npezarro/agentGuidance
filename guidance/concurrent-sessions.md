<!-- Load when: several sessions share one checkout; worktrees, resource locks, claim-guard, "it keeps reverting" -->
# Concurrent Sessions on the Same Repo

Several Claude sessions run in this home dir at once (seven live on 2026-08-01), all with
`--dangerously-skip-permissions`, all sharing one checkout per repo. Collisions have been
recurring since 2026-07-17 and each fix has narrowed the window without closing it.

**The reason it keeps recurring: this is two problems, and one mechanism was being asked to
solve both.**

| | Problem A: shared working tree | Problem B: singletons |
|---|---|---|
| What | N sessions, one checkout. Index + working tree are mutable shared state with no ownership. | `/var/www/<app>`, PM2 services, the live browser extension, `~/.claude/skills`, the VM. Exactly one exists. |
| Symptom | `git add -A` commits someone else's uncommitted work; two sessions commit the same file seconds apart. | One session's deploy overwrites another's; two `ext-reload`s tear down each other's service worker. |
| Right fix | **Eliminate the sharing** (per-session git worktrees). | **Serialize** (a real lock) or **partition** (one owner per path). |
| Wrong fix | Detection. It can only narrow the race. | Advisory warnings. You can proceed past them, so nothing is serialized. |

`claim-guard.sh` is good at what it does and correctly caught a real hazard on 2026-08-01,
but it is detection applied to both columns. Keep it as the backstop, not the strategy.

## Problem A: use a worktree per session

```
EnterWorktree                 # creates .claude/worktrees/<name> on a new branch
... do the work, commit ...
ExitWorktree { action: keep|remove }
```

**`EnterWorktree` is often unavailable here, and the rule used to assume it wasn't.** The
tool requires the SESSION cwd to be inside a git repo, but this ecosystem launches sessions
from `/mnt/c/Users/npeza` (not a repo) and they routinely span several repos at once. An
instruction that cannot be followed is worse than none: it gets silently skipped, and that
erodes the rest of the file.

The mechanism is git worktrees; `EnterWorktree` is one convenience wrapper. From anywhere:

```bash
git -C ~/repos/<repo> worktree add .claude/worktrees/<n> -b <n>
# then edit via ~/repos/<repo>/.claude/worktrees/<n>/...
git -C ~/repos/<repo> merge --no-ff <n> && git -C ~/repos/<repo> push
```

Verified 2026-08-03 from a non-repo cwd: the worktree was created, `worktree-guard` treated
the path as isolated (it keys on the target file path, not cwd, precisely so this works),
and `check-unpushed` caught a stranded commit there as
`activity-tracker (worktree xrepo)`. The whole mechanism works cross-repo; only the tool
does not.

Then there is no other session's uncommitted work in your tree, so `git add -A` is safe
**by construction** and the whole class disappears.

Why this is cheap here, contrary to expectation: worktrees live under
`.claude/worktrees/`, so the canonical `~/repos/<repo>` **stays exactly where it is**. The
78 crontab lines and 14 PM2 `ecosystem.config.js` files that hardcode `/home/npezarro/repos/<repo>`
keep working untouched. They get better, in fact: crons start running against a clean
committed tree instead of one that several sessions are mid-edit on.

Real costs, stated honestly:
- Each session ends with a merge back to master. Added ceremony for solo work.
- Git refuses the same branch in two worktrees. That is a feature (it forces per-session
  branches), but it is a behavior change.
- Zero help for Problem B.
- Separate clones are unaffected either way. The browser-agent Windows checkout at
  `/mnt/c/Users/npeza/Documents/repos/browser-agent` is still its own clone and still has
  to be pulled before `ext-reload`.

### The ignore rule is GLOBAL (2026-08-03), no per-repo step needed

```bash
git config --global core.excludesFile ~/.gitignore_global   # contains .claude/worktrees/
```

Set on both the WSL host and the VM, mirrored at `privateContext/claude-config/gitignore_global`.

Originally this was a per-repo `.gitignore` line, which does not scale: **118 of 123 repos
lacked it**, and adding it to each would have meant 118 commits across repos other sessions
are live in. One global config covers every repo including ones created later. Verified in a
repo with no local entry: `git status` stayed clean with a worktree open, and
`check-ignore` attributed the match to the global file.

Caveat: a global excludes file is machine-local and not shared with collaborators. Fine for
a solo two-machine setup; a repo with outside contributors still wants the committed line.
The five repos that already carry it locally keep it, harmlessly.

For reference, the line itself:

```
.claude/worktrees/
```

Without it the worktree directory shows up as `?? .claude/` in the **canonical** tree, so a
`git add -A` there commits an entire nested worktree. Measured on browser-agent 2026-08-01:
unignored, `git status` in the canonical checkout listed `?? .claude/` the moment a worktree
existed. Ignoring it is what makes the canonical tree stay clean.

### Proof it does what it claims

Reproducing today's exact clobber, with session B in a worktree:

```
canonical tree (session A):   M CLAUDE.md        <- A's uncommitted edit
worktree      (session B):    echo >> progress.md ; git add -A
B staged:                     M  progress.md      <- only its own file
A's CLAUDE.md edit:           untouched
```

Same command that captured another session's work today, now inert.

### Two hook fixes worktrees REQUIRED, both shipped 2026-08-02

Worktrees were invisible to the push gate, so a session could commit in one, never merge,
and stop with no warning at all — trading a loud problem (clobber, which you notice) for a
silent one (stranded work, which you do not). Verified silent beforehand: empty output,
exit 0. Two independent causes, both fixed in `hooks/check-unpushed.sh`:

- `.git` is a **directory** in a normal checkout but a **file** in a linked worktree, so
  the `-d` entry test skipped every worktree ledger entry.
- A worktree branch has **no upstream**, so `@{u}` failed and the unpushed check was
  skipped. It now compares against origin's default branch, because for such a branch the
  question is not "pushed to my upstream" but "does this work exist on the remote yet".

### What NOT to do: collapsing a worktree onto its canonical repo

Tempting (claim-guard keys ledgers on repo root, so a worktree looks like a separate
repo), and wrong twice over. Tried and reverted 2026-08-02:

- The ledger would key on the canonical root while the file lives in the worktree, so
  `rel_path` resolves to `.claude/worktrees/<name>/…`, which is **gitignored there** and
  reports clean. Dirty worktree files would look committed.
- Two sessions in separate worktrees genuinely **cannot** clobber each other's working
  tree, so cross-warning them is a false positive. Per-working-tree scoping is correct.

One related subtlety if you touch `wti_repo_root`: run its `check-ignore` test against the
tree the file actually lives in. Testing a worktree file against the canonical repo reports
every one of them ignored (because of the `.gitignore` entry above) and the session goes
completely invisible to the guards.

### Enforcement: `hooks/worktree-guard.sh` (PreToolUse, 2026-08-02)

The `agent.md` rule is advisory, so a `PreToolUse` hook on `Edit|Write` backs it. It denies
the **first write** to a repo when all three hold:

1. the target is inside a repo under the guarded root (`~/repos`, override
   `WORKTREE_GUARD_ROOT`), **and**
2. it is not already inside `.claude/worktrees/`, **and**
3. another **live** session has written **that same file**.

**Condition 3 was originally "holds that repo", and that was wrong.** Production disagreed
within ~15 minutes: two denials against a real peer on `knowledgeBase` and
`privateContext`, with **zero overlapping files** in both, and that session acked both
rather than taking a worktree. Repo-level co-presence is the normal state when several
sessions run; it is not a collision. What it actually risks, a stage-everything commit
sweeping a peer's uncommitted work, is already blocked by claim-guard's deny arm, so the
wider condition bought friction and no protection.

Two bugs surfaced while narrowing it, both worth knowing if you touch ledger matching:
ledger paths are absolute but **not normalized** (a real entry contained `/./`, which
fails plain equality against a realpath'd target and would have made the guard silently
never fire), and an unquoted heredoc expands variables but does **not** interpret `\n`.

Condition 3 is what makes this enforcement rather than friction: a solo session in an
uncontested repo never sees it. Escape hatch (shared with claim-guard, so one override
covers both):

```bash
printf '%s\t%s\n' '<repo-name>' '<reason>' >> /tmp/claude-claim-ack-<sid>
```

**Why PreToolUse and not Stop**, which is the intuitive choice: at Stop the editing has
already happened in the shared checkout, so blocking cannot retroactively isolate
anything — there is no remediation left, only nagging. Stop also cannot distinguish
"correctly skipped" from "forgot", so it would fire on the exempt cases too and train
reflexive acks. Stop's correct job here is already done by `check-unpushed.sh`: catching
work *stranded in a worktree*, i.e. "did your work escape this machine", not "did you use
the workflow".

Keyed on the target **file path**, not `cwd`: editing an absolute canonical path from
inside a worktree is still unisolated, and `cwd` would call that safe.

Tests: `hooks/tests/test-worktree-guard.sh` (13 cases). Verified live — a real `Write` to
a contested repo was blocked, the file was not created, and the ack let the retry through.

**Status: enabled by default** (`agent.md`, Core Principles) for multi-edit work in
`~/repos`. Skip for read-only work, one-file edits and ops. `.gitignore` prerequisite
applied to agentGuidance, knowledgeBase, privateContext, claude-skills, browser-agent — add
it to any other repo before working in a worktree there.

**Deploys read the canonical checkout**, not your worktree: merge and push before running a
deploy or `ext-reload`, or you will ship the pre-worktree code.

## Problem B: take a real lock

`scripts/with-resource-lock.sh` serializes an operation on a named singleton:

```bash
with-resource-lock.sh <resource> [--timeout N] -- <command...>
with-resource-lock.sh --list          # who holds what right now
```

Resource naming scheme (keep it stable, the string IS the lock):

| Resource | Covers |
|---|---|
| `deploy:<app>` | `/var/www/<app>`, that app's PM2 service |
| `browser-extension` | the live Chrome extension: reload, CDP, tab state |
| `vm:skills` | `~/.claude/skills` on the VM |

Wired in:

| Resource | Where |
|---|---|
| `browser-extension` | `browser-cli ext-reload` self-wraps (`BROWSER_AGENT_NO_LOCK=1` opts out) |
| `vm:skills` | `claude-skills/sync.sh` — replaces the hand-run rsync pair; also counts SKILL.md across all three copies and fails on a mismatch |
| `deploy:<app>` | the `deploy` and `staging` skills. Wired at the skill, not in 10+ per-repo `deploy.sh` files, because the ecosystem rule is already that deploys go through these skills |

## Hygiene and monitoring

**`scripts/reap-session-ledgers.sh`** (hourly cron). Sessions never clean up their `/tmp`
state. Measured 2026-08-03: 299 files, 1.1MB, **59 alive markers for ~2 live sessions**.
Two harms, neither cosmetic: the raw marker count misleads anyone who reads it, and
claim-guard iterates every ledger on each qualifying command. Reaps at 24h (48x
`LIVE_WINDOW`) with a hard 2h floor that refuses any shorter age, because a too-eager reap
would silently blind the guards rather than fail loudly.

**`scripts/guard-calibration-report.sh`** (daily cron). Alerts when a guard is being
**routed around**, which is the failure nothing was watching for. The signal is the
override rate, not the deny count: a guard that fires and is obeyed works; one that fires
and gets overridden is indistinguishable from an absent one.

Counts **distinct sessions**, not log lines. One ack decision logs a line on every
subsequent write, so a line-based rate inflates without bound, and a first pass nearly
tuned the threshold against the test suite's own synthetic ids. First real reading:

```
worktree-guard   sessions denied=3, of which overrode=3 (100%)
claim-guard      sessions denied=5, of which overrode=0   (0%)
```

Every real session that hit worktree-guard routed around it. Both known causes (repo-level
matching, and reading the heuristic ledger) are now fixed; the guard is **unproven** and
this report is what will say whether the fixes took.

Behavior worth knowing:
- Backed by `flock(2)`, so the kernel releases the lock when the holder exits **including
  on crash or SIGKILL**. A dead session can never wedge a resource. Verified.
- Waiting past `--timeout` exits **75** (`EX_TEMPFAIL`), distinct from the wrapped
  command's own failures, and names the holder.
- Re-entrant within one process tree via `CLAUDE_HELD_LOCKS`, so a locked script calling
  another locked script does not deadlock against itself.

### The gotcha this script exists to have already solved

A child process **inherits the lock file descriptor**. Without care, wrapping anything that
daemonizes (`pm2 restart`, any `nohup`/`setsid` service) hands the inherited fd to a process
that outlives the deploy, and the resource is locked *forever*. That is strictly worse than
no lock. The script runs the command as `"$@" 9>&-` to close the fd in the child. If you
write another lock wrapper, do the same, and verify with:

```bash
for p in $(ls /proc | grep -E '^[0-9]+$'); do
  ls -l /proc/$p/fd 2>/dev/null | grep -q "claude-resource-lock-<name>" && echo "holds: $p"
done
```

Only the wrapper's own pid should appear.

## The backstop: claim-guard

Detection cannot serialize anything, so this is the third line, not the strategy. It earns
its place by catching the case both columns above miss: two sessions that never took a
worktree and never took a lock, writing the same path right now.

`hooks/claim-guard.sh`, two modes:

| | When | Behavior |
|---|---|---|
| `warn` | PostToolUse `Bash\|Edit\|Write` | Names the other live session when it wrote the same file (or the same repo). Deduped: once per path per peer session. |
| `deny` | PreToolUse `Bash` | Exit 2 on `git add -A/--all/.`, `git commit -a/--all`, and `rsync --delete` into `/var/www/<app>` when a live peer holds that repo or deploy target. |

Supporting pieces:

- `hooks/lib/write-target-inference.sh` infers which files a Bash command writes. Heredocs,
  redirects and `sed -i` are invisible to a `file_path` tracker, and the 2026-07-30
  near-miss happened on exactly such a write. Precision beats recall here: a bare `python3`
  is not a write, only one whose body writes.
- `hooks/session-heartbeat.sh` also writes `/tmp/claude-session-alive-<sid>` per session
  (headless included). Without per-session liveness the guard fires on `/tmp` ledgers left
  by sessions that exited weeks ago.
- Two ledgers: `/tmp/claude-repos-touched-<sid>` is Edit/Write only (authorship, feeds the
  Stop gate); `/tmp/claude-repos-claimed-<sid>` is Bash-inferred (advisory, guard only).
  Heuristics must never reach a gate that blocks a session's exit.

**Escape hatch, because a denial must never be a dead end:**
`printf '%s\t%s\n' '<target>' '<reason>' >> /tmp/claude-claim-ack-<sid>`. Denials, overrides
and unresolvable targets all land in `~/.claude/logs/claim-guard.log`.

**Registration.** The scripts are versioned in this repo; the wiring lives in
`~/.claude/settings.json`, which is in no repo. Mirror and drift-check:
`privateContext/claude-config/` (`sync-settings.sh --check`). Restore by hand with:

```jsonc
// PreToolUse, matcher "Bash"
"bash -c 'printf \"%s\" \"$(cat)\" | bash $HOME/repos/agentGuidance/hooks/claim-guard.sh deny'"
// PostToolUse, matcher "Bash|Edit|Write"  (track first, then guard)
"bash -c 'printf \"%s\" \"$(cat)\" | bash $HOME/repos/agentGuidance/hooks/track-repo-writes.sh; exit 0'"
"bash -c 'printf \"%s\" \"$(cat)\" | bash $HOME/repos/agentGuidance/hooks/claim-guard.sh warn; exit 0'"
// PostToolUse, matcher "Bash|Edit|Write|NotebookEdit"  (was `cat >/dev/null`, must now pipe)
"bash -c 'printf \"%s\" \"$(cat)\" | bash $HOME/repos/agentGuidance/hooks/session-heartbeat.sh; exit 0'"
```

The `deny` entry deliberately omits `exit 0`: swallowing its exit code turns the block into
a no-op.

### Closed gaps (both were reported here first)

- **False-positives on the command's own text** (was `claim-guard.sh:170-171`). Two
  uncorrelated greps meant a commit message *describing* the dangerous command was denied
  as if it were the command. Fixed 2026-08-01 (`eb76be0`): the command is split into
  segments (heredoc bodies dropped, `ssh <host> '<remote>'` unwrapped, string literals
  removed before arguments are read) and each segment is judged by its own leading command
  and argument list. Covered by three regression tests: quoted `-m` message, heredoc commit
  body, `echo` of the string.
- **The Stop gate was repo-granular** (`check-unpushed.sh`). Fixed 2026-08-01 (`eb76be0`):
  each unpushed commit's files are intersected against this session's Edit/Write ledger, so
  it blocks only on commits containing files this session wrote. A peer's unpushed commits
  are now *reported* rather than blocked, pointing at the push-to-their-branch procedure in
  `git-workflow.md`.

### Remaining gap

A `cd` target built from a variable assigned in an *earlier* turn cannot be resolved (a
variable assigned in the same command now can be). The deny arm logs `unresolved-target`
rather than passing silently, so the blind spot is auditable. The warn arm still fires on
the writes themselves.

## Diagnostic order when something "keeps reverting"

Before blaming cache or cron, see `learning_concurrent_session_clobber` and KB
`patterns/shared-checkout-concurrent-sessions.md`. Short version: `stat` the origin file
against your deploy time, then `git log -- <path>` for foreign commits, then map live
sessions with `/tmp/claude-session-alive-*`.

**Do not kill a live session to win a race.** It is usually Nick's own. Check whether its
tree is clean and pushed, then ask.

### gitignore node_modules/ with a trailing slash does not ignore a node_modules symlink (2026-08-04)
When you follow the WORKTREE RULE and create a worktree to run a repo's tests, the worktree has no `node_modules`. The quick fix is to symlink the main checkout's: `ln -s /path/to/repo/node_modules node_modules`.

That symlink is NOT covered by the near-universal `.gitignore` entry `node_modules/`. A pattern with a trailing slash matches directories only, and to git a symlink is a *blob* (mode 120000), not a directory. So `git add -A` silently stages the symlink, and it lands in the commit and the PR as a one-line file whose contents are an absolute path from your home directory.

Two consequences, both bad: the diff leaks a local absolute path (an infrastructure identifier), and anyone checking the branch out gets a dangling symlink where their dependencies should be.

Detection: `git diff --staged --stat` before every commit, and treat a `node_modules` row in the stat output as a stop sign. `git status` will also show it as an untracked *file*, not swallow it the way it swallows a real node_modules directory.

Fix: `git rm --cached node_modules` before committing. To prevent it repo-wide, use the slash-less form `node_modules` in `.gitignore`, which matches a directory OR a file OR a symlink of that name.

Generalizes past node_modules: any `.gitignore` entry written as `name/` will miss a symlink called `name` (`dist/`, `build/`, `.next/`, `coverage/`, `venv/`). Symlinking a heavy build/dependency directory into a worktree is exactly the workflow that trips it, so this is a standing hazard of the worktree pattern rather than a one-off.

### A node_modules SYMLINK is not matched by a 'node_modules/' gitignore rule, so linking deps into a worktree makes it stageable by git add -A (2026-08-04)
Git worktrees created with 'git worktree add' have no node_modules, so tsc/build need one linked or installed. Linking it (ln -s ../../node_modules) then makes 'git status' show '?? node_modules' -- UNTRACKED, not ignored -- because a gitignore pattern with a trailing slash ('node_modules/') matches only a directory, and a symlink is a file. A 'git add -A' in that worktree would commit a symlink pointing at an absolute path on one machine.

Seen 2026-08-04 across shopper, foodie and travel-assistant simultaneously; all three .gitignore files use the trailing-slash form, so all three were exposed.

Rules:
1. After linking node_modules into a worktree, ALWAYS 'rm' the symlink before committing, and prefer 'git add <explicit paths>' over 'git add -A' in a worktree.
2. Read 'git status --short' before every commit in a worktree and treat any unexpected '??' entry as a stop, not noise. This is the same class as shopper's existing '.env.bak*' warning: an ignore rule that looks like it covers a path may not cover the FORM the path takes.
3. If you want the link to be ignored, the pattern must be 'node_modules' (no trailing slash).

### A Next.js standalone build inside a worktree nests its output, so the artifacts must never be deployed (2026-08-05)
Next's standalone output mirrors the project directory *relative to the repo root*. Built from the primary checkout it lands at `.next/standalone/.next/`; built from a worktree it lands at `.next/standalone/<worktree-path>/.next/`. The shared build script line used verbatim by shopper, foodie, travel-assistant, employ and runeval then fails:

```
next build && rm -rf .next/standalone/.next/static && cp -r .next/static .next/standalone/.next/static
# cp: cannot create directory '.next/standalone/.next/static': No such file or directory
```

The compile itself SUCCEEDS and every route is listed, so the run reads as passing right up to the `cp` error on the final line. Verified in a shopper worktree on 2026-08-05: output landed at `.next/standalone/.claude/worktrees/billing-entitlements/.next/`.

Rules:
1. **Never deploy artifacts from a worktree build.** The static assets sit where the standalone server will not serve them, which reproduces exactly the unstyled-page failure the `fix-static-asset-drift` skill exists to repair.
2. Treat that `cp` failure as a hard stop, not a cosmetic warning. It is the signal that the output tree is not the shape the deploy expects.
3. A worktree build is still the right way to *typecheck and validate* a change. Merge to the default branch, then build from the primary checkout to produce anything deployable.

### git add inherits a shared staging area: a pre-commit secret gate can block YOUR commit over a peer session's content (2026-08-07)
SYMPTOM: you stage one clean file, and the pre-commit secret-scan blocks the commit citing line numbers and identifiers that do not appear anywhere in your file.

CAUSE: several sessions share one checkout, so the git INDEX is shared state too. A peer session had already staged 8 other files. Your 'git add <one-file>' adds to that existing index, and the gate scans the whole staged diff, not just your path. Hit on 2026-08-07 in wordpressPosts: 8 peer-staged posts carried real repo-name and ssh identifier leaks.

DO NOT: 'git commit --no-verify'. The gate was right; the leaks are real. Committing bypasses it for the peer's content, not just yours.
DO NOT: 'git reset' or 'git stash'. Reset is fine here in practice but broad, and stash TOUCHES THE WORKING TREE, which can yank files out from under a live peer session mid-write.

DO: unstage the peer's paths by name, leaving the working tree untouched, then commit only yours.
  git diff --cached --name-only            # see whose files are actually staged
  git restore --staged <peer-path> ...     # index only; files stay on disk
  git diff --cached --name-only            # confirm only yours remains
  git commit && git push

Their content is preserved on disk and loses nothing: it could not have been committed anyway while the gate was blocking it. Report the blocked files as an open item so the leaks get fixed rather than silently re-staged.

GENERAL RULE: before commiting in a shared checkout, always run 'git diff --cached --name-only' and confirm every staged path is yours. Related: pattern_concurrent_sessions_two_problems, learning_concurrent_session_clobber.

### Two agents on one Chrome profile must claim targets in a file before the first fill (2026-08-07)
Two Claude jobs ran the same library-signup task against the same browser-agent profile (keyIdx 0) at once. Symptoms: tabs appearing that this session did not open, and 'Timeout waiting for browser response' on roughly every other command.

Detect it, do not guess: 'browser-cli.sh logs 300' prints per-consumer lines like '[17861403] Exec: clickAny ...' — consumer IDs that are not yours are another agent. Cross-check with 'ps' start times against your own PID chain.

Interleaved fill/click on a shared profile silently corrupts the other agent's half-filled form, and duplicate submissions to the same institution risk a duplicate-patron record. Resolution that worked: a CLAIMS.md in the shared working dir listing PID -> target, appended to BEFORE the first fill on a new target, plus an explicit statement in the final report that the other job's targets are its to report, not yours. Never assert an outcome for a target another agent drove — you cannot verify it.

### Two Discord-dispatched Claude jobs can share one Chrome profile and one scratch dir; read the claims file before the first fill or you duplicate a sibling's signups (2026-08-07)
On 2026-08-07 a single Discord request produced TWO concurrent Claude jobs (PID 272628 at 14:18 PT and PID 413575 at 15:05 PT) both driving the SAME browser-agent Chrome profile (keyIdx 0) and both writing to ~/library-signup/.

The 14:18 job wrote ~/library-signup/CLAIMS.md as a coordination guard, claiming targets before driving each form. The 15:05 job never read it and re-drove a claimed target (Monterey County Free Libraries), submitting a duplicate registration. It was rejected by vendor de-duplication ('A patron record matching these details already exists'), and the 15:05 job then misread that rejection as proof its OWN submit had succeeded — writing a false success into its results file and appending a bogus second PIN to the shared .pw.

Detection signals that a sibling job is live in your workspace:
- a file in your scratch dir you did not create (here: CLAIMS.md, and an extra .pw line)
- `browser-cli tabs` showing tabs for sites unrelated to your task
- 'Another debugger is already attached to the tab with id: N' from cdp-* commands
- your own PID tree not matching the PID recorded in the claims file

Rules:
1. Before the first `fill` on a new target, list your scratch dir and READ any claims/lock file.
2. Append your PID + target to it before driving.
3. Never treat a vendor 'record already exists' response as evidence your own submit worked — it is equally consistent with a sibling having done it. Verify by logging in, or check the claims file.
4. Target tabs by explicit tab id, and assert the URL before acting; `focus` matches any Chrome tab including ones the relay is not tracking, so a loose URL substring can silently drive the wrong page.
