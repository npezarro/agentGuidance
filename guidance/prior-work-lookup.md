<!-- Load when: finding past conversations and prior work -->
# Prior Work Lookup — Where to Search for Past Conversations

When a user says "we did this before" or "our previous work on X", search these sources in order:

## 0. Recall Index (fastest for conversational content; WSL host only)
A local FTS5 + semantic index of ALL past Claude Code sessions (~114K turn-blocks) lives at
`~/repos/session-recall`. This is the first place to look when the prior work was a *conversation*
(a decision, a debugging arc, an exact command) rather than a committed file.
```bash
R=~/repos/session-recall/recall
$R "kroger token refresh 401"                 # keyword — error strings, commands, names
$R "static asset drift" --project shopper --since 2026-06-01
$R --semantic "why did we abandon the local worker bridge"   # meaning-based questions
$R show <session-id>:<line>                    # expand a hit with surrounding context
```
Bodies are scrubbed; do not paste raw `recall` output into external surfaces without re-scrubbing.
Run `~/repos/session-recall/reindex.sh` if the index looks stale. (Only on the WSL host — the VM
and other machines don't have the index; use sources 1-6 there.)

## 1. Git History (fastest, most reliable)
- `git log --all --oneline --grep="<keyword>"` in the relevant repo
- `git log --all --oneline -- <file>` for specific file changes
- Check all branches including stale/WIP ones
- Check `git stash list` for uncommitted work

## 2. Closeout Reports
- `~/repos/privateContext/deliverables/closeouts/` — per-session closeout markdown files
- WordPress blog posts via `search-wp-posts.sh "<keyword>"` (script at `~/repos/agentGuidance/scripts/search-wp-posts.sh`)
- Closeouts contain detailed summaries of what was done, decisions made, and what's left

## 3. Discord Channels
Bot token and guild ID are in `privateContext/accounts.md` under Discord section.
Channel IDs for key channels (#requests, #cli-interactions, #job-search, #running-job-logs, #cli-mirror) are also in `accounts.md`.

Search pattern: fetch the bot token from the VM, then use the Discord API to search channel messages:
```bash
# See privateContext/accounts.md for token retrieval and channel IDs
curl -s -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
  "https://discord.com/api/v10/channels/<CHANNEL_ID>/messages?limit=100" | \
  python3 -c "
import json, sys
msgs = json.load(sys.stdin)
for m in msgs:
    if '<keyword>' in m.get('content','').lower():
        print(f'{m[\"timestamp\"][:16]} | {m[\"content\"][:300]}')
"
```
Use `before=<message_snowflake>` parameter to paginate backward through history.

## 4. GitHub PRs and Issues
```bash
gh search prs "<keyword>" --owner npezarro --limit 20
gh search issues "<keyword>" --owner npezarro --limit 20
gh search commits "<keyword>" --owner npezarro --limit 20
```

## 5. Context/Progress Files
- `context.md` and `progress.md` in each repo — handoff notes between sessions
- `~/repos/privateContext/deliverables/` — broader deliverables

## 6. Memory
- `~/.claude/projects/-mnt-c-Users-npeza/memory/` — auto-memory system
- Check existing memory files for project context

## Gaps
- On the WSL host, the recall index (source 0) captures conversation history verbatim even when a
  session produced no commit, closeout, or Discord post — as long as the session ran on this host
  and the index has been refreshed (`reindex.sh`, also hourly via cron).
- Remaining gap: sessions that ran ONLY on the VM or another machine are not in the local recall
  index. #cli-interactions (which recall also ingests) is the cross-machine backstop, but only
  captures logged turns. For those, still rely on closeouts, commits, and Discord posts.
- Closeouts remain valuable for substantive work: they add human-readable synthesis the raw index
  lacks, and they cover the cross-machine gap.
