# Debugging Guidance

A systematic approach to diagnosing and fixing issues.

## The Debugging Workflow

```
0. Gather Context → 1. Reproduce → 2. Read the Error → 3. Isolate → 4. Hypothesize → 5. Verify → 6. Fix → 7. Confirm
```

### 0. Gather Existing Knowledge First

Before touching code or forming hypotheses, check whether this problem (or a closely related one) has been solved before:

- **Memory**: Read relevant feedback/project memory files — corrections from past sessions are your highest-signal source
- **CLAUDE.md**: The repo's CLAUDE.md documents architecture decisions and known gotchas
- **Guidance**: Check `agentGuidance/guidance/` for domain-specific rules (auth-basepath.md, deployment.md, etc.)
- **Wiki**: Scan knowledgeBase wiki index for cross-repo patterns
- **privateContext**: Check for credentials, registered URIs, or infrastructure details that constrain the solution
- **Git history**: `git log --oneline --grep="<keyword>"` to find prior fixes

This is not optional background reading — it's the most efficient debugging step. **The previous session's fix is often already documented in memory.** Skipping this to "save time" causes multi-hour debugging loops.

### Approach Switching (15-minute rule)

If you've been trying variations of the same approach for 15+ minutes without progress:
1. Stop iterating on the current approach
2. Re-read memory/guidance for the domain (Step 0 again)
3. Spawn a debugger agent for a fresh perspective
4. Try a **fundamentally different** approach

Repeating the same category of fix with different values is not debugging — it's brute force.

### 1. Reproduce the Issue

Before touching code, confirm you can trigger the problem:
- Run the exact command or action that causes the error.
- Note the exact error message, stack trace, and context.
- If you can't reproduce it, you can't confidently fix it.

### 2. Read the Error Fully

- Read the **entire** stack trace, not just the first line.
- Look for the **first** error in a chain — cascading failures often hide the root cause.
- Check if the error message directly tells you what's wrong (it often does).

### 3. Isolate the Problem

- **Binary search:** Comment out half the suspect code. Does the error persist?
- **Minimal reproduction:** Can you trigger it with a 5-line script?
- **Check boundaries:** Is the issue in your code, a dependency, or the environment?

### 4. Check the Obvious First

Before diving deep, rule out:

```bash
# Am I on the right branch?
git branch --show-current

# Is the latest code deployed/running?
git log --oneline -3

# Are env vars loaded?
echo $NODE_ENV
cat .env | head -5  # (don't log secrets)

# Are deps up to date?
npm ls <suspect-package>
npm install

# Is the right version running?
node -v
npm -v

# Any port conflicts?
ss -tlnp | grep <port>

# Disk space?
df -h

# Permissions?
ls -la <file>
```

### 5. Targeted Debugging

Add **focused** logging — not scattered `console.log("here")`:

```javascript
// Bad
console.log("here");
console.log("here2");

// Good
console.log('[DEBUG] processOrder input:', { orderId, items: items.length });
console.log('[DEBUG] processOrder result:', { status, total });
```

### 6. Use Git to Find What Changed

```bash
# What changed recently?
git log --oneline -20

# What's different from the working version?
git diff HEAD~3

# Find the exact commit that broke it
git bisect start
git bisect bad          # current commit is broken
git bisect good <hash>  # this commit was working
# Git will binary-search through commits
```

### 7. Common Patterns

| Symptom | Likely Cause |
|---------|-------------|
| `MODULE_NOT_FOUND` | Missing dependency, wrong path, missing build step |
| `EACCES` / permission denied | File ownership issue (`sudo chown`) |
| `EADDRINUSE` | Port already in use — kill the other process or use a different port |
| `TypeError: x is not a function` | Wrong import, wrong version, or `x` is undefined |
| `undefined` where you expect data | Async issue, wrong property name, missing await |
| Works locally, fails in CI | Different Node version, missing env vars, different OS |
| Works on first load, breaks on refresh | Client-side state not synced with server, stale cache |
| Script silently produces empty results | Path from JSON/jq contains `~` — not expanded by shell. Use `${VAR/#\~/$HOME}` |

### 8. After Fixing

- Remove all debug logging before committing.
- Write a regression test if possible.
- Document the root cause in the commit message.
- Update `context.md` if the fix reveals something about the environment.

### 9. SQLite & Prisma Specifics

- **Database is locked**: In SQLite, concurrent writes cause locking.
  - **Fix**: Move updateMany or createMany calls OUT of loops. Consolidate into a single operation per user/batch.
  - **Pragma**: Use PRAGMA busy_timeout=5000; to make SQLite wait instead of failing immediately.
- **executeRawUnsafe vs queryRawUnsafe for PRAGMAs**: Use `$queryRawUnsafe` for **both** `PRAGMA journal_mode=WAL` and `PRAGMA busy_timeout=5000`. Catch and ignore `"Execute returned results"` — it means the PRAGMA worked. Log all other errors.
  ```ts
  prisma.$queryRawUnsafe(`PRAGMA journal_mode=WAL;`).catch((err) => {
    if (!err.message?.includes("Execute returned results")) console.error("WAL enable failed:", err);
  });
  prisma.$queryRawUnsafe(`PRAGMA busy_timeout=5000;`).catch((err) => {
    if (!err.message?.includes("Execute returned results")) console.error("busy_timeout failed:", err);
  });
  ```
- **`connection_limit=1` required for SQLite in Next.js.** Next.js spawns multiple worker threads; without this they contend for the SQLite file and cause "Database is locked". Add to DATABASE_URL:
  ```
  DATABASE_URL="file:./production.db?connection_limit=1&timeout=30&pool_timeout=30"
  ```
  Source: runeval required 7 commits to stabilize on this (2026-05-15).
- **Prisma singleton: always assign to global, even in production.** The common guard `if (process.env.NODE_ENV !== 'production')` before `globalForPrisma.prisma = prisma` is wrong — Next.js worker threads reload modules without reinitializing globals. Remove the guard:
  ```ts
  export const prisma = globalForPrisma.prisma || createPrisma();
  globalForPrisma.prisma = prisma;  // always, not just in dev
  ```
  Source: finance-tracker OOM crash loop until this guard was removed (2026-05-15).
- **Next.js apps OOMing under load:** Increase heap in PM2 ecosystem.config:
  ```js
  env: { NODE_OPTIONS: '--max-old-space-size=1024' }
  ```
  Also raise `max_memory_restart` to match (e.g., `1G`). Source: finance-tracker (2026-05-15).
- **`datetime('now')` strings parse as LOCAL time in `new Date()`, not UTC.** SQLite stores UTC as `"YYYY-MM-DD HH:MM:SS"` (space-separated, no `T`/`Z`). The ECMAScript Date parser treats that non-ISO form as local time, so rendering a stored timestamp via `new Date(created_at)` silently shifts it by the viewer's UTC offset (7-8h for Pacific users), and can shift the displayed date near UTC midnight. This bites both Prisma-on-SQLite and raw `better-sqlite3` apps alike — it's a JS Date-parsing bug, not a Prisma one.
  - **Fix**: normalize before parsing — strict-match `/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/` and rewrite to `` `${date}T${time}Z` ``; pass already-ISO strings through unchanged. SQL-side comparisons like `date(created_at) = utcToday` are unaffected (both sides stay UTC).
  - Source: foodie `LocalTimestamp.tsx` (PR #48, 2026-07-06) fed raw DB strings straight to `new Date()` at 3 call sites. Verified: `new Date('2026-07-06 12:00:00').toISOString()` → `19:00Z` on a PDT host. shopper, travel-assistant, and employ carry identical `LocalTimestamp.tsx` clones with the same bug (grep-confirmed, not yet ported).

### 10. Prisma + PostgreSQL: Use pg.Pool, Not Raw Connection String

When using `@prisma/adapter-pg` (PrismaPg), pass a `pg.Pool` instance for proper connection pool control:

```ts
import { PrismaPg } from "@prisma/adapter-pg";
import { Pool } from "pg";

const pool = new Pool({
  connectionString: process.env.DATABASE_URL!,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });
```

`new PrismaPg({ connectionString })` creates an unmanaged pool with no limits. Source: finance-tracker refactor (2026-05-16).

### 11. Tools Run by a `claude -p` Agent Must Be Non-Interactive

A Discord/automation flow that dispatches work to a `claude -p` agent runs with no TTY. Any CLI the agent invokes that blocks on interactive input (e.g. a `readline` "approve/edit?" prompt) will hang silently, and the agent will quietly fall back to a worse path (or time out). Symptoms: "the tool exists and is wired up, but the nice pipeline never seems to actually run."

Fixes:
- Give the tool an `--auto`/`--yes` flag AND auto-enable it when `!process.stdin.isTTY`, so it never hangs regardless of how it's launched.
- Don't depend on an `ANTHROPIC_API_KEY` for sub-steps — route model calls through the `claude -p` CLI (subscription auth) so the tool runs in the same keyless environment as the agent.
- Make the tested tool the canonical path; prompts that re-describe a "manual fallback" flow drift and silently lose features (e.g. pricing).

Source: fb-marketplace-poster consolidation (2026-05-27) — main.js readline confirm + SDK key dependency forced the Discord agent into a fallback prompt that skipped shopper pricing. See `privateContext/deliverables/closeouts/2026-05-27-fbm-shopper-resale-pricing.md`.

### 12. Browser CDP Timeout Recovery — Kill + Restart Pattern (2026-06-10)

When a service calls a browser-agent CLI and receives "Timeout waiting for browser response", the Chrome/CDP session is stuck (not just slow). Recovery requires:

1. Detect the specific timeout error string in your error handler
2. Kill all chrome/chromium processes: `pkill -f chrome || true`
3. PM2-restart the browser-agent service: `pm2 restart browser-agent`
4. Implement a startup connectivity check that triggers recovery *before* the main task:

```js
async function checkBrowserConnectivity() {
  try {
    await runBrowserCLI(['status'], { timeout: 10000 });
  } catch (err) {
    if (err.message.includes('Timeout waiting for browser response')) {
      await restartBrowserSystem();
    }
  }
}

async function restartBrowserSystem() {
  execSync('pkill -f chrome || true');
  execSync('pm2 restart browser-agent');
  await new Promise(resolve => setTimeout(resolve, 3000)); // wait for startup
}
```

Also increase the base CLI timeout from 60s to 120s to avoid false-positive timeouts on slow page loads (separate from CDP hangs).

Source: reddit-referral-poster commit 48af749 (2026-06-10) — CDP sessions were silently hanging after connectivity loss; retries piled up with no recovery.
