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

## Incident 9: SSH User Mismatch — WSL vs Windows Username

**Date:** 2026-04-11
**Trigger:** The reverse SSH tunnel terminates at Windows OpenSSH, which authenticates with the Windows username. The executor was configured with the WSL/Linux username as the default SSH user, so connections failed.
**Resolution:** Changed the default SSH user to the Windows username. Added an environment variable override (`LOCAL1_SSH_USER`) so the value isn't hardcoded.
**Prevention rule:** **When the tunnel path crosses a WSL/Windows boundary, remember that Windows OpenSSH uses the Windows username, not the WSL username.** These are often different. Always make SSH usernames configurable via environment variables rather than hardcoding either one.

## General Rules for Multi-Environment Deployments

1. **Test the full path, not just components.** SSH tunnel test, project detection test, unknown project test, team mode test — each individually.
2. **Deploy includes `npm install`.** Never skip it after pulling changes.
3. **Check re-export chains.** The codebase has a pattern where intermediate modules re-export — new exports need to traverse the full chain.
4. **Command dispatch is not auto-wired.** New commands need updates in both the handler and the router regex.
5. **Strip user input noise.** Mentions, extra whitespace, flags — clean the input before matching.
6. **Dynamic paths over hardcoded paths.** Environment detection > hardcoded paths > nothing.
