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

**Status: browser-agent is the trial repo** (`.gitignore` updated). Roll out per-repo rather
than globally, and only after a repo's cron/PM2 assumptions have been eyeballed.

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

## Known gap: claim-guard false-positives on the command's own text

`hooks/claim-guard.sh:170-171` runs two independent greps over the **whole** command
string: one for `git add`, one for a bare `-A` / `--all` / `.` token anywhere. They are
never correlated to the same command segment, so a commit message that *describes* the
dangerous command is denied as if it were the dangerous command. Hit 2026-08-01 while
committing this very file: the message contained the words `git add -A`, and staging an
explicit path was blocked.

This matters more than it looks. A guard that fires on safe commands trains you to ack
reflexively, which quietly disables it.

Fix: correlate the two patterns, i.e. match the argument list of the `git add` invocation
itself rather than scanning the full string. Not yet implemented.

## Known gap: the Stop gate is repo-granular

`hooks/check-unpushed.sh` reads the session's touched-**repos** ledger, then asks
`git rev-list @{u}..HEAD --count`. So touching any file in a repo makes a session
responsible for *every* unpushed commit in it, including another live session's. This fired
on 2026-08-01: a session was told to push a two-minute-old commit from a different session.

Fix: for each unpushed commit, intersect `git show --name-only` against the session's file
ledger (`/tmp/claude-repos-touched-<sid>` already stores paths) and only block on commits
containing files this session actually wrote. Not yet implemented.

## Diagnostic order when something "keeps reverting"

Before blaming cache or cron, see `learning_concurrent_session_clobber` and KB
`patterns/concurrent-session-clobber.md`. Short version: `stat` the origin file against your
deploy time, then `git log -- <path>` for foreign commits, then map live sessions with
`/tmp/claude-session-alive-*`.

**Do not kill a live session to win a race.** It is usually Nick's own. Check whether its
tree is clean and pushed, then ask.
