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

### Per-repo rollout step, do this FIRST

Add to the repo's `.gitignore`:

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
3. another **live** session holds that repo.

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

Wired in so far: `browser-cli ext-reload` (self-wraps; set `BROWSER_AGENT_NO_LOCK=1` to opt out).

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
