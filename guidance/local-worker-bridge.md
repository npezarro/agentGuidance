# Local Worker Bridge — Lessons Learned

Post-mortem from the local worker bridge setup (2026-03-16 to 2026-03-18). Documents issues encountered during setup and deployment so agents avoid repeating them.

## Architecture Overview

The Discord bot runs on GCP VM (4GB RAM). Jobs route to a local PC (40GB RAM) via SSH reverse tunnel when available, with VM as fallback. The routing decision is automatic based on tunnel heartbeat status.

```
VM executor → ssh REDACTED_TUNNEL → reverse tunnel → Windows OpenSSH → wsl-shell.bat → WSL bash → run-claude
```

## Incident 1: Unknown Project Fallback Crash

**Date:** 2026-03-17
**Trigger:** When no project was detected from user input, `resolveProjectDir()` returned `DEFAULT_CWD` (`/home/REDACTED_USER`). `path.basename()` extracted `REDACTED_USER` as the project name and sent it to the local worker. The local worker had no such project directory and crashed with `ERROR: Project directory not found`.
**Resolution:** Local worker now falls back to `~/repos` (DEFAULT_CWD) instead of erroring when the project directory doesn't exist.
**Prevention rule:** **Always test with unrecognized/default project names**, not just known ones. Fallback paths must be graceful, not fatal.

## Incident 2: Re-export Chain Breakage

**Date:** 2026-03-17
**Trigger:** Added `runClaudeRemoteTeam` to `executor.js` and imported it in `debate.js`, but `debate.js` actually imports from `claudeReply.js` (which re-exports executor functions). The function was missing from the re-export chain, causing `teamRunFn is not a function` at runtime.
**Resolution:** Added `runClaudeRemoteTeam` to both the import and re-export sections of `claudeReply.js`.
**Prevention rule:** **When adding a new export to executor.js, always check and update the re-export chain in claudeReply.js.** The import graph is: `debate.js → claudeReply.js → executor.js`. Grep for existing re-exports before assuming direct imports work.

## Incident 3: Command Regex Missing New Commands

**Date:** 2026-03-17
**Trigger:** `!autonomous test 5` posted in `#requests` was treated as a debate request instead of a command. The `isBuiltinCommand` regex in `index.js` was missing `autonomous`, so the request handler processed it first.
**Resolution:** Added `autonomous` to the regex.
**Prevention rule:** **When adding a new `!command` to commands.js, always add it to the `isBuiltinCommand` regex in index.js too.** These are separate and not auto-synced.

## Incident 4: Bot Mention Prefix Breaks Command Detection

**Date:** 2026-03-17
**Trigger:** User typed `@Bot !autonomous test 5`. Discord resolves mentions to `<@ID>` prefix in `message.content`, so the actual string was `<@123> !autonomous test 5`. The `^!` regex anchor required `!` at position 0, which failed.
**Resolution:** Strip leading `<@ID>` mentions from `message.content` before regex matching and command dispatch.
**Prevention rule:** **Never assume `message.content` starts with the command text.** Users often @ mention the bot before typing commands. Always strip mention prefixes before matching.

## Incident 5: Missing npm Dependencies After Large Sync

**Date:** 2026-03-18
**Trigger:** A large git pull brought new files (logger.js, autonomousLoop.js, etc.) that required `pino`. `npm install` was not run on the VM after the pull, causing `Cannot find module 'pino'` crash loop.
**Resolution:** Ran `npm install` on the VM.
**Prevention rule:** **After any git pull that changes `package.json` or `package-lock.json`, always run `npm install` before restarting.** Automate this in the deploy script if possible.

## Incident 6: Hardcoded Paths Across VM/WSL Boundary

**Date:** 2026-03-18
**Trigger:** `taskDiscovery.js` had `REPOS_JSON_PATH` hardcoded to `/home/npezarro/repos/...` (WSL path). The bot runs on the VM where that path doesn't exist. The autonomous agent's discovery scan found no repos.
**Resolution:** Made the path resolution dynamic — try WSL path first, then VM path. Made `repos_root` auto-detect based on which directory exists. Added `AUTONOMOUS_REPOS_ROOT` env override.
**Prevention rule:** **Never hardcode absolute paths that only exist on one machine.** When code runs on both VM and local, use environment variables or dynamic detection. Test on both environments.

## Incident 7: Windows Line Endings (CRLF) in WSL Scripts

**Date:** 2026-03-16 (recurred 2026-03-17)
**Trigger:** Scripts edited or created through Windows got CRLF line endings. WSL bash interprets `\r` as part of the command, causing `bash\r: No such file or directory`.
**Resolution:** `sed -i 's/\r$//'` on affected scripts.
**Prevention rule:** **After creating or editing any script file that will run in WSL, always check for and strip CRLF line endings.** Consider adding a `.gitattributes` with `*.sh text eol=lf`.

## Incident 8: WSL localhost vs Windows Host IP

**Date:** 2026-03-16
**Trigger:** `autossh -R 2222:localhost:22` from WSL forwards to WSL's own localhost, not Windows sshd. The tunnel connected but SSH through it reached WSL instead of Windows OpenSSH.
**Resolution:** Use the Windows host IP from `/etc/resolv.conf` nameserver (e.g., `REDACTED_WSL_IP`) instead of `localhost`.
**Prevention rule:** **In WSL, `localhost` refers to WSL's network stack, not Windows.** For Windows services (sshd, etc.), use the host IP from `/etc/resolv.conf`. This IP can change across restarts — resolve it dynamically.

## General Rules for Multi-Environment Deployments

1. **Test the full path, not just components.** SSH tunnel test, project detection test, unknown project test, team mode test — each individually.
2. **Deploy includes `npm install`.** Never skip it after pulling changes.
3. **Check re-export chains.** centralDiscord has a pattern where `debate.js → claudeReply.js → executor.js` — new exports need to traverse the full chain.
4. **Command dispatch is not auto-wired.** New commands need updates in both `commands.js` (handler) and `index.js` (regex + context).
5. **Strip user input noise.** Mentions, extra whitespace, flags — clean the input before matching.
6. **Dynamic paths over hardcoded paths.** Environment detection > hardcoded paths > nothing.
