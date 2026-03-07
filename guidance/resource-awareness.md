# Resource Awareness

Shared infrastructure has limits. Discover them before you hit them — don't memorize numbers that change.

## Principle: Discover, Don't Memorize

Server specs change (VMs get resized, processes get added, disk fills up). Never hardcode thresholds in your mental model. Instead, **check before every heavy operation**.

## Before Heavy Work

Run these checks before starting builds, installs, large file operations, or anything CPU/memory-intensive:

```bash
# Memory — is there enough for a build?
free -m

# Disk — is there room for node_modules, build output, logs?
df -h

# What's already running? How many processes, how much memory?
pm2 jlist 2>/dev/null | python3 -c "
import sys, json
procs = json.load(sys.stdin)
for p in procs:
    print(f\"{p['name']:20s} {p['pm2_env']['status']:8s} {p['monit']['memory']//1024//1024}MB\")
" 2>/dev/null || pm2 list

# CPU load
uptime
```

If memory is tight (< 500MB free) or disk is low (< 1GB), flag it before proceeding. Don't silently start a build that will OOM-kill something else.

## Output Size Awareness

Large responses create problems downstream:
- Discord embeds truncate at ~3,900 characters — anything beyond is lost
- WordPress posts become walls of text that nobody reads
- Terminal output floods the user's scrollback

**Keep responses focused.** If you need to output large content (full file listings, extensive logs, audit results), write it to a file and reference the path. Don't dump it into your response.

## Concurrent Job Awareness

On shared infrastructure, you're probably not the only process running:
- **Check before starting resource-intensive work.** `pm2 list` shows what else is running. If three other agent sessions are active, a `npm install` might push the server over.
- **Check `#running-job-logs`** (if Discord is available) to see if other Claude sessions are active on the same server.
- **Don't spawn parallel builds** on a constrained VM. Sequential is slower but won't OOM.

## Environment Variable Awareness

Before starting work on any deployed project:
- **Check if env vars are loaded:** `echo $NODE_ENV`, check `.env` exists
- **Understand the build/restart distinction:** Static site generators (Next.js, Vite) bake env vars at build time. Changing `.env` requires a full rebuild, not just a PM2 restart
- **Check `MAX_CONCURRENT_JOBS`** or equivalent throttle settings in the environment before spawning background processes
