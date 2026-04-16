# Prior Work Lookup — Where to Search for Past Conversations

When a user says "we did this before" or "our previous work on X", search these sources in order:

## 1. Git History (fastest, most reliable)
- `git log --all --oneline --grep="<keyword>"` in the relevant repo
- `git log --all --oneline -- <file>` for specific file changes
- Check all branches including stale/WIP ones
- Check `git stash list` for uncommitted work

## 2. Closeout Reports
- `~/repos/privateContext/deliverables/closeouts/` — per-session closeout markdown files
- WordPress blog posts via `search-wp-posts.sh "<keyword>"` (script at `~/repos/agentGuidance/hooks/search-wp-posts.sh`)
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

## GitHub Link References

When the user shares a GitHub link pointing to files in a repo under `~/repos/`, always `git pull` the repo to get the files locally. Don't say the files don't exist or ask the user to provide them separately — the link is a pointer to files already in a known repo.

## Gaps
- Claude Code conversation history is NOT persisted between sessions unless captured in a closeout, commit, or Discord post
- If a conversation produced no commit, no closeout, and no Discord post, it's effectively lost
- Always encourage closeouts for substantive work to prevent this
