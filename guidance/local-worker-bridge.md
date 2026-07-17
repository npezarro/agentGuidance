<!-- Load when: local worker bridge post-mortem -->
# Local Worker Bridge — Lessons Learned

Post-mortem from the local worker bridge setup (2026-03-16 to 2026-03-18). Documents issues encountered during setup and deployment so agents avoid repeating them.

## Architecture Overview

The Discord bot runs on a cloud VM (limited RAM). Jobs route to a local PC (high RAM) via SSH reverse tunnel when available, with VM as fallback. The routing decision is automatic based on tunnel heartbeat status.

```
VM executor → ssh reverse tunnel → local machine SSH → shell → run-claude
```

## Incident 1: Unknown Project Fallback Crash

**Date:** 2026-03-17
**Trigger:** When no project was detected from user input, `resolveProjectDir()` returned the default working directory. `path.basename()` extracted an unexpected directory name as the project name and sent it to the local worker, which had no such project directory and crashed.
**Resolution:** Local worker now falls back to a default repos directory instead of erroring when the project directory doesn't exist.
**Prevention rule:** **Always test with unrecognized/default project names**, not just known ones. Fallback paths must be graceful, not fatal.

## Incident 2: Re-export Chain Breakage

**Date:** 2026-03-17
**Trigger:** Added a new function to `executor.js` and imported it in `debate.js`, but `debate.js` actually imports from `claudeReply.js` (which re-exports executor functions). The function was missing from the re-export chain, causing a runtime error.
**Resolution:** Added the function to both the import and re-export sections of `claudeReply.js`.
**Prevention rule:** **When adding a new export to executor.js, always check and update the re-export chain in claudeReply.js.** The import graph is: `debate.js → claudeReply.js → executor.js`. Grep for existing re-exports before assuming direct imports work.

## Incident 3: Command Regex Missing New Commands

**Date:** 2026-03-17
**Trigger:** A new command posted in the requests channel was treated as a debate request instead of a command. The `isBuiltinCommand` regex in `index.js` was missing the new command name.
**Resolution:** Added the command to the regex.
**Prevention rule:** **When adding a new `!command` to commands.js, always add it to the `isBuiltinCommand` regex in index.js too.** These are separate and not auto-synced.

## Incident 4: Bot Mention Prefix Breaks Command Detection

**Date:** 2026-03-17
**Trigger:** User typed `@Bot !command args`. Discord resolves mentions to `<@ID>` prefix in `message.content`, so the `^!` regex anchor failed.
**Resolution:** Strip leading mention prefixes from `message.content` before regex matching.
**Prevention rule:** **Never assume `message.content` starts with the command text.** Users often @ mention the bot before typing commands. Always strip mention prefixes before matching.

## Incident 5: Missing npm Dependencies After Large Sync

**Date:** 2026-03-18
**Trigger:** A large git pull brought new files requiring a new dependency. `npm install` was not run after the pull, causing a module-not-found crash loop.
**Resolution:** Ran `npm install` on the VM.
**Prevention rule:** **After any git pull that changes `package.json` or `package-lock.json`, always run `npm install` before restarting.** Automate this in the deploy script if possible.

## Incident 6: Hardcoded Paths Across VM/WSL Boundary

**Date:** 2026-03-18
**Trigger:** A path was hardcoded to a WSL-specific location. The bot runs on the VM where that path doesn't exist, so the discovery scan found nothing.
**Resolution:** Made the path resolution dynamic — try local path first, then VM path. Added an environment variable override.
**Prevention rule:** **Never hardcode absolute paths that only exist on one machine.** When code runs on both VM and local, use environment variables or dynamic detection. Test on both environments.

## Incident 7: Windows Line Endings (CRLF) in WSL Scripts

**Date:** 2026-03-16 (recurred 2026-03-17)
**Trigger:** Scripts edited or created through Windows got CRLF line endings. WSL bash interprets `\r` as part of the command, causing errors.
**Resolution:** `sed -i 's/\r$//'` on affected scripts.
**Prevention rule:** **After creating or editing any script file that will run in WSL, always check for and strip CRLF line endings.** Consider adding a `.gitattributes` with `*.sh text eol=lf`.

## Incident 8: WSL localhost vs Windows Host IP

**Date:** 2026-03-16
**Trigger:** Reverse tunnel forwarding to `localhost` from WSL reached WSL's own network stack, not Windows services.
**Resolution:** Use the Windows host IP (from `/etc/resolv.conf` nameserver) instead of `localhost`.
**Prevention rule:** **In WSL, `localhost` refers to WSL's network stack, not Windows.** For Windows services, use the host IP from `/etc/resolv.conf`. This IP can change across restarts — resolve it dynamically.

## General Rules for Multi-Environment Deployments

1. **Test the full path, not just components.** SSH tunnel test, project detection test, unknown project test, team mode test — each individually.
2. **Deploy includes `npm install`.** Never skip it after pulling changes.
3. **Check re-export chains.** The codebase has a pattern where intermediate modules re-export — new exports need to traverse the full chain.
4. **Command dispatch is not auto-wired.** New commands need updates in both the handler and the router regex.
5. **Strip user input noise.** Mentions, extra whitespace, flags — clean the input before matching.
6. **Dynamic paths over hardcoded paths.** Environment detection > hardcoded paths > nothing.

### Docker single-file bind mounts capture inode, not path (2026-05-28)
**Symptom:** A container that bind-mounts a single host file (e.g. `~/.claude/.credentials.json`) keeps serving stale contents after the host atomically replaces that file. Inside the container, `stat` shows `Links: 0` and an mtime from before the host rotation.

**Why:** Docker single-file bind mounts capture the source by inode at container start. When the host writes via rename-into-place (which Claude CLI `/login`, editors, and most config writers do), the inode changes but the container still points at the original (now unlinked) inode.

**How to apply:**
- For credentials/configs that rotate on the host, restart the container after host-side rotation. The bridge-auth-refresh.sh cron does this automatically based on /health.
- Better long-term fix: bind-mount the parent directory (`/path/to/.claude:/home/node/.claude:ro`) instead of a single file. Directory mounts re-read on each open.
- Tell-tale diagnostic: `docker exec <container> stat <path>` showing `Links: 0` confirms the inode-replacement scenario.

Discovered 2026-05-28 while debugging foodie + shopper + travel bridges returning auth:failed after host `claude /login`.

### OAuth Max in headless containers needs explicit lifecycle handling (2026-05-28)
**Rule:** Containers wrapping `claude -p` for unattended use cannot rely on the CLI's interactive re-auth flow. Refresh tokens expire on a clock (not on inactivity), so keepalive traffic does nothing — only re-auth helps.

**Why:** Anthropic OAuth Max sessions auto-refresh access tokens on each CLI invocation, but the refresh token itself has a fixed lifetime (~30-60 days per Anthropic's current policy). When the refresh token expires, no amount of CLI traffic recovers it — the host must run `claude /login` interactively.

**How to apply:** Any container that wraps `claude -p` needs three things:
1. A /health endpoint that exposes auth state (e.g. `{"auth":"ok|failed|pending","authError":"..."}`).
2. A watcher cron that restarts the container on stale credentials (handles the inode trap — see [[pattern_docker-bind-mount-inode-trap]]).
3. A Discord alert when restart fails to restore auth (signals the host itself needs /login).

Reference implementation: `~/repos/scripts/bridge-auth-refresh.sh` runs every 10min for shopper, foodie, and travel bridges. Do NOT add synthetic keepalive traffic — it's wasted tokens and doesn't extend refresh-token lifetime.

For truly unattended workloads, prefer API key auth (`ANTHROPIC_API_KEY` env var) over OAuth Max.

### Bridge /health endpoints must expose auth state, not just liveness (2026-05-28)
**Rule:** Any container that wraps an auth-dependent CLI must expose auth state via /health, not just process liveness.

**Why:** Generic 5xx errors from the bridge ("AI service temporarily unavailable") collapse three distinct root causes — auth failure, rate limit, transient API error — into the same surface. Without /health distinguishing them, a 5-minute fix becomes a 2-hour log dive. The shopper/foodie bridge `/health` returns `{"auth":"ok|failed|pending","authError":"..."}`, which turned a multi-day mystery into a 30-second diagnosis.

**How to apply:** When building a new Claude-CLI-wrapping bridge:
1. Run an auth probe at container start and periodically (every ~60s).
2. Expose the latest result on /health alongside queue depth and active job count.
3. The probe can be a no-op query like `claude -p "ok"` — cheap, exercises the full auth path.
4. Pair with [[pattern_oauth-max-headless-containers]] for the cron-driven recovery flow.

Reference implementation: foodie/shopper/travel bridge-server.js auth probe + health endpoint.

### Bridge server self-exit on persistent auth failure (2026-05-28)
**Rule:** Claude-CLI-wrapping bridge servers should exit with `process.exit(1)` after N consecutive auth failures, relying on Docker's restart policy to bring the container back fresh.

**Why:** Even with an external `bridge-auth-refresh.sh` cron, there's a window (up to 10min) where the bridge serves `auth:failed` responses. The self-exit pattern closes this window — the bridge itself detects the stale credential state and triggers an immediate restart, picking up the new inode after `claude /login`.

**How to implement:**
```js
let consecutiveAuthFailures = 0;
const MAX_AUTH_FAILURES = 3; // 3 × 30min = 90min before self-exit

function checkAuth() {
  // ... run probe ...
  if (isOk) {
    consecutiveAuthFailures = 0;
  } else {
    consecutiveAuthFailures++;
    if (consecutiveAuthFailures >= MAX_AUTH_FAILURES) {
      console.error(JSON.stringify({ event: "auth_persistent_failure", msg: "Exiting for Docker restart" }));
      process.exit(1); // Docker restarts container fresh, picking up new credential inode
    }
  }
}
```

**Requirements:** Docker service must have `restart: unless-stopped` (or `always`) policy. Do NOT use this pattern with bare PM2 processes — exit(1) will not restart the process with fresh credentials.

**Interaction with cron:** The cron (`bridge-auth-refresh.sh`) and self-exit are complementary. The cron handles scheduled recovery; self-exit handles the case where the cron hasn't fired yet (or misses a run). Both are needed.

Source: foodie commit 8a35730, shopper commit f4d935b, travel commit 51950cc (2026-05-27).

### Unbounded per-call batch size causes silent 0-result failures (2026-07-16)
**Rule:** Never ask one headless `claude -p` bridge call for an unbounded or large batch of results under a fixed timeout. Bound the batch size per call and paginate across multiple calls instead; make the response parser tolerant of truncated output.

**Why:** employ's "Exhaustive" discovery tier asked a single bridge call to find 45-70 roles. The call either over-ran the bridge's 10-minute timeout (SIGTERM'd mid-generation) or hit the model's output-token ceiling, leaving a truncated response with no closing JSON fence. The parser returned `[]` on the malformed JSON, so the run reported "found 0 roles" with no error surfaced. Worse, the downstream augment/expand safety net also refused to run because it requires a non-empty initial set — so the failure compounded to a total of 0 instead of degrading gracefully.

**How to apply:**
1. Cap every bridge call at a fixed max batch size (employ uses `MAX_ROLES_PER_CALL=25`) regardless of how large the requested total is; accumulate toward the full target across multiple passes instead.
2. Soften "as many as possible, even if it takes longer" style prompt directives for large-breadth tiers — aim each call at the per-call cap, not the grand total.
3. Retry once on a 0-result parse before treating it as a real empty result.
4. Harden the parser to merge all fenced JSON blocks in a response and recover complete objects from truncated/unclosed JSON via a balanced-brace scan, rather than failing the whole batch on one truncation.

Source: employ commits `06e979e` (fix) and `df111d8` (scale window/batch by depth), 2026-07-16.

### Enforce subprocess timeouts with SIGTERM to SIGKILL; keep bridge budget under client timeout (2026-07-17)
Node.js child_process spawn({ timeout }) only sends ONE SIGTERM when the timeout elapses. Long-running CLIs like 'claude -p' (and their child processes / streaming API sockets) can ignore SIGTERM, so the process hangs and the promise never settles — leaving the server holding the request open until the CLIENT aborts. Enforce timeouts yourself: an explicit setTimeout that escalates SIGTERM -> SIGKILL after a grace period, a 'settled' guard flag so close/error settle once, and a distinct 'timeout' rejection (map to HTTP 504). Also keep a bridge's TOTAL work budget strictly under its client's timeout (e.g. 18min bridge < 20min client < 25min recovery threshold), and for multi-pass work (first pass + refinement) split that budget against a single deadline so the bridge returns a real, diagnosable error BEFORE the client gives up with an opaque 'Request timed out (20min)'. Surface the internal reason (exit code / spawn error, sanitized) on the catch-all 500 so downstream [RECOVERY FAILED] alerts are debuggable. Applies to all pezant *-bridge servers (shopper/foodie/travel/employ) which share this bridge-server.js shape. Root cause: shopper Job #96 recovery loop, 2026-07-17.
