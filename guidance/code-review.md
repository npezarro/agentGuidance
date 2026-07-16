<!-- Load when: self-review checklist before committing -->
# Code Review Guidance

Self-review checklist to run before every commit and PR.

## Pre-Commit Checklist

### 1. Correctness
- [ ] Does the change solve the stated problem?
- [ ] Are edge cases handled (empty input, null, zero, negative numbers)?
- [ ] Are error states handled at system boundaries?
- [ ] Does async code properly `await` and handle rejections?

### 2. No Regressions
- [ ] Build passes: `npm run build`
- [ ] Tests pass: `npm test`
- [ ] Existing functionality still works (manual spot-check if no tests)

### 3. Security
- [ ] No secrets, API keys, tokens, or passwords in the diff
- [ ] No hardcoded credentials or URLs with auth info
- [ ] User input is validated/sanitized at entry points
- [ ] SQL/NoSQL queries use parameterized inputs (no string interpolation)
- [ ] No `eval()`, `innerHTML`, or `dangerouslySetInnerHTML` with user data

### 4. Code Quality
- [ ] Variable and function names are descriptive and follow existing conventions
- [ ] No dead code, commented-out blocks, or debug `console.log` statements
- [ ] No duplicated logic that should be extracted
- [ ] Functions do one thing and are reasonably short
- [ ] Complex logic has a brief comment explaining *why*

### 5. File Hygiene
- [ ] No unintended files staged (`.DS_Store`, `node_modules/`, build output, `.env`)
- [ ] Lockfiles (`package-lock.json`) are updated if dependencies changed
- [ ] No unrelated changes mixed into the commit

### 6. Git Hygiene
- [ ] Commit message explains *why*, not just *what*
- [ ] Commit is on the correct branch (not `main`)
- [ ] `git diff --staged` reviewed line by line

## PR Review Checklist

When opening a PR, also verify:

### 7. PR Scope
- [ ] PR addresses a single concern (one feature, one bug, one refactor)
- [ ] PR title is clear and under 70 characters
- [ ] PR description explains what changed and why
- [ ] Reviewer can understand the change without prior context

### 8. Testing Evidence
- [ ] Describe how the change was tested
- [ ] Include test output or screenshots if applicable
- [ ] Note any areas that need manual testing

### 9. Deployment Impact
- [ ] Any environment variable changes documented
- [ ] Any migration or data changes noted
- [ ] Rollback plan identified for risky changes

## Protected Configuration (Do Not Remove)

Some configuration properties look like dead code but are essential for production. Never remove these during fix or cleanup runs without verifying the deployment context:

- **NextAuth/Auth.js**: `basePath`, `redirectProxyUrl`, provider `authorization.params`, `token.params` — required for subpath deployments behind reverse proxies. See `agentGuidance/guidance/auth-basepath.md`.
- **PM2 ecosystem.config.js**: `env`, `max_memory_restart`, `cwd` — essential for production process management.
- **Apache/proxy config references in code**: URL construction that includes basePaths or proxy prefixes.

**Why:** autonomousDev crash-fix run #134 removed `basePath` and `redirectProxyUrl` from finance-tracker's auth.ts because they appeared unused. This broke OAuth on the subpath deployment, requiring a manual restore (60db078).

## Default Review Workflow: Review-Ship-Review

Unless the user explicitly requests a single review pass, use the iterative review-ship-review pattern for all non-trivial code changes. This is the default.

### How it works

1. **Implement** — Make the requested changes, run tests, commit.
2. **Review (round 1)** — Spawn 2-3 parallel reviewer agents. Each agent audits the diff independently, categorizing findings as Critical / Important / Minor / Deferred.
3. **Fix & commit** — Address all Critical and Important findings. Commit the fixes.
4. **Review (round 2)** — Spawn fresh reviewer agents on the updated code. Reviewers must not see prior review output; they audit with fresh eyes. This catches regressions introduced by the fixes and surfaces issues the first round missed.
5. **Repeat** — If round 2 produces Critical or Important findings, fix and run another round. Stop when a review round returns clean (no Critical/Important findings). Minor and Deferred items can be noted but don't block.

### Why this is the default

Single-pass reviews miss bugs that only become visible after fixes land. In practice, fix commits introduce new issues 30-40% of the time (wrong variable reuse, stale state, interaction between fixes). The second review round catches these before they ship.

### Reviewer agent instructions

Each reviewer agent should:
- Read all changed files (not just the diff) to understand full context
- Check for interactions between changes (e.g., a risk check fix that bypasses a downstream guard)
- Verify test coverage for new logic paths
- Flag shell injection, state mutation bugs, and off-by-one errors
- Categorize each finding: **Critical** (breaks correctness or security), **Important** (likely bug or missing coverage), **Minor** (style, naming), **Deferred** (nice-to-have, not blocking)

### When to skip

- Trivial changes (typo fixes, comment updates, config value changes)
- User explicitly says "just commit" or "skip review"
- Single-line fixes with obvious correctness

## Common Issues to Watch For

| Pattern | Problem | Fix |
|---------|---------|-----|
| `catch (e) {}` | Swallowed error | Log or rethrow |
| `array.length > 0 ? array[0] : undefined` | Verbose | `array[0]` (already undefined if empty) |
| `if (x == null)` | Loose equality | `if (x === null \|\| x === undefined)` or keep `== null` if intentional |
| `async` function with no `await` | Unnecessary async wrapper | Remove `async` keyword |
| `new Date()` in business logic | Untestable | Inject time as parameter |
| String concatenation for paths | OS-incompatible | Use `path.join()` |
| Prisma `globalForPrisma` dev-only cache | Connection leak in production | Cache on `globalThis` unconditionally (see below) |
| `new Date("2026-04-15")` for display | UTC parse → local timezone off-by-one | Use `new Date(year, month, day)` for local dates |
| Shell-interpolating JSON into script strings | Special chars break syntax | Write to temp file, read in target language (see below) |
| Hardcoded timezone offset `timedelta(hours=-4)` | Breaks at DST transitions | Use `ZoneInfo('America/New_York')` or equivalent TZ library |
| `head -c N` before parsing structured output | Silent data loss — truncation drops blocks downstream code depends on | Size limit to max expected output, or extract specific fields first |
| `res.json({ error: err.message })` | Information disclosure — leaks paths, DB strings, stack traces | Return generic message, log details server-side (see below) |
| `child_process.exec(cmd + userInput)` | Command injection via string interpolation | Use `execFile(binary, [args])` with separate args array (see below) |
| In-memory `Map` keyed by external input (IP, user ID) with no eviction | Unbounded memory growth — every new key is a permanent entry | Sweep expired entries lazily on access, or cap size with an LRU |
| `useEffect(() => setState(...), [prop])` to reset state when a prop changes | Flagged as an error (not warning) by modern `eslint-plugin-react-hooks` (`set-state-in-effect`); also costs an extra render pass | Adjust state during render instead: `const [prev, setPrev] = useState(prop); if (prop !== prev) { setPrev(prop); setState(reset); }` |

## Error Detail Leak Prevention

Never expose raw error messages, stack traces, internal paths, hostnames, or database connection strings in HTTP responses. This is OWASP "Improper Error Handling" and was found in 6+ repos during a 2026-05 audit.

```js
// ❌ Leaks internal paths, DB connection strings, etc.
catch (error) {
  res.status(500).json({ error: error.message });
  // or: res.status(500).json({ error: 'Failed', details: String(error) });
}

// ✅ Generic message to client, full error logged server-side
catch (error) {
  console.error('Route /api/foo failed:', error);
  res.status(500).json({ error: 'Internal server error' });
}
```

**Common leak vectors:** `details: String(error)`, `error: err.message`, `os.hostname()` in health endpoints, MulterError raw messages, CLI exit codes in spawn error handlers.

**Affected repos (fixed 2026-05):** health-hub, freeGames, manchu-translator, auto-shorts, claude-auto-merger, promptlibrary.

## Unbounded In-Memory Maps (Rate Limiters, Caches)

A `Map` (or plain object) keyed by request-derived input — IP address, user ID, session token — that only ever adds entries has no natural upper bound. Every distinct key becomes a permanent resident; under real traffic (or a scripted probe hitting many IPs) this is a slow memory leak that only shows up after days of uptime, not in a quick smoke test.

**Real case (manchu-translator, commit `db872c1`, 2026-07-15):** `lib/rate-limiter.js` maintained a module-level `ipMap` incremented on every `/api/translate` request, with no removal path — expired-window entries stayed forever. Fixed with a lazy, once-per-window `sweep()` that deletes only already-expired entries (called opportunistically on access, not via a separate timer), plus a `size()` export so tests can assert the map stops growing.

**Self-review trigger:** any module-level `Map`/`Set`/object keyed by an externally-controlled value (IP, user ID, session ID, request ID) — ask "what removes an entry, and when?" If the answer is "nothing", add eviction (lazy sweep on access is usually simplest; reach for a proper LRU only if access patterns need it) and a size assertion in tests.

## Command Injection: exec vs execFile

Never use `child_process.exec()` with string interpolation for user-influenced values. `exec()` runs through a shell, so semicolons, backticks, and pipe characters in the input become shell commands.

```js
// ❌ Command injection — url could contain `; rm -rf /`
exec(`open "${url}"`);

// ✅ execFile bypasses the shell entirely
execFile('open', [url]);
```

**Why:** freeGames `openInBrowser()` passed user-controlled URLs through `exec()`. Fixed in run #253 by switching to `execFile()` with a URL validation guard rejecting non-http(s) protocols.
| `if (secret === input)` | Timing attack leaks secret length/content | Use `crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b))` |
| `new URL(userInput)` without scheme check | SSRF via `file://`, `data://`, `javascript://` | Validate `url.protocol` is `http:` or `https:` before use |
| `path.join(base, userInput)` unsanitized | Path traversal via `../` sequences | Strip `..`, leading `/`, and non-alphanumeric chars from user path segments |
| `Infinity` in API responses | `JSON.stringify(Infinity)` === `"null"`, client sees `null` not a number | Use a large finite number (e.g., `999999`) for "unlimited" values sent over JSON |
| Tailwind `@apply text-blue-600` in CSS | `@apply` with certain utility classes silently drops from compiled output | Use raw CSS values (`color: #2563eb`) instead of `@apply` for critical styles |

## Prisma globalThis Singleton — Always Cache in Production

The standard Next.js Prisma pattern only caches the client in development:

```ts
// ❌ Bug: production creates new clients on duplicate module loads
if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = prisma;
```

With adapters like `@prisma/adapter-libsql`, production can also load the module multiple times, leaking connections. Always cache unconditionally:

```ts
// ✅ Prevents connection leaks in both dev and production
globalForPrisma.prisma = prisma;
```

**Affected repos:** botlink, finance-tracker (still have the dev-only guard). health-hub fixed this in commit 8ed8356.

## Shell → Script Data Passing — Use Temp Files

Never embed JSON or structured data into script strings via shell variable expansion. Quotes, newlines, and special characters in the data will corrupt the target language syntax.

```bash
# ❌ Breaks when JSON contains quotes, newlines, or $
python3 -c "
import json
data = json.loads('''$JSON_VAR''')
"

# ✅ Write to temp file, read in target script
TMPFILE=$(mktemp)
echo "$JSON_VAR" > "$TMPFILE"
python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
" "$TMPFILE"
rm -f "$TMPFILE"
```

**Why:** trading-agent run.sh was silently producing malformed Python when news article titles contained special chars. Temp files eliminate all shell escaping concerns.

**Also applies to:** Node.js (`--eval` with interpolated strings), Ruby, any language invoked from bash with dynamic data. Use stdin piping (`echo "$JSON" | python3 script.py`) as an alternative to temp files.

## Timezone Offsets — Never Hardcode

Don't use fixed UTC offsets like `timedelta(hours=-4)` or `new Date().getTimezoneOffset()` for business logic that must respect DST transitions.

```python
# ❌ Breaks every March and November
eastern = timezone(timedelta(hours=-4))

# ✅ Auto-handles EST/EDT
from zoneinfo import ZoneInfo
eastern = ZoneInfo('America/New_York')
```

**Why:** trading-agent's market-hours check used hardcoded EDT offset, causing zero executions during EST months. The cron schedule was also wrong because UTC hours were interpreted as local time.

## Output Truncation Causes Silent Parse Failures

When bash scripts use `head -c N` or `head -n N` to limit command output before extracting structured blocks (via `grep`, `jq`, etc.), the truncation can silently drop the block downstream code depends on. The result is an empty match — not an error — so failures are invisible.

**Example:** `head -c 2000` on Claude CLI output truncated the `ACTIVITY_OBSERVED:` block that Discord threading depended on. The script ran without errors but produced empty summaries for weeks.

**Fix:** Either size the limit to the maximum expected output (e.g., `head -c 10000` for Claude output), or extract the specific field first and truncate the extracted value. Never truncate structured output before parsing it.

## Structured Output Format Compliance

When a prompt specifies a strict output format (e.g., "ONLY valid JSON", "no markdown fences", "no explanation"), enforce it before submitting:

1. **Parse the constraint first** — read the format requirement exactly.
2. **Validate before submitting** — after writing the response, check it against the constraint.
3. **Fix, don't annotate** — if a violation is found: STOP, regenerate correctly. Never submit both the violation and a self-diagnosis of it.

**Common violations:** wrapping JSON in fences when told not to; adding explanatory text when told "no explanation"; submitting a self-diagnosis inside the violating output.

**Why:** Multiple scoring sessions (2026-05-15) violated this pattern and then self-diagnosed the violation inside the same response — demonstrating the agent knew the rule and still didn't fix it. Hard format constraints are enforcement gates for downstream parsers. Identifying a violation is not fixing it.

## Update CLAUDE.md When Adding Features

After implementing a new feature, route, export, or command, update the repo's CLAUDE.md before committing. Documentation lag is structural — close it at commit time. (Graduated from ESSENTIAL 2026-06-10: the CLAUDE.md drift-check PostToolUse hook now flags commits that add exports/routes/env vars without a CLAUDE.md update.)

### Isolate per-item failures in batch loops; guard operations that throw on stored/external data (2026-06-30)
When a loop processes a batch (DB rows, files, API records) and each iteration does an operation that can throw on bad data, an unguarded throw aborts the ENTIRE batch — not just the bad item. Two-layer defense: (1) guard the throwing operation itself (e.g. compile a stored regex via a safeCompile() that returns null on SyntaxError; JSON.parse external files in try/catch; check divisor != 0 before dividing on externally-sourced deltas), and (2) wrap each loop iteration in try/catch + continue so one bad record is skipped, not fatal. Real case (finance-tracker PR #74): benefit auto-detection compiled 'new RegExp(template.merchantPattern)' from stored card-benefit template strings at 3 sites with no guard, inside detectAllBenefits() which looped mappings with no try/catch. One malformed pattern threw SyntaxError and 500'd /api/cards/detect, killing detection for ALL the user's cards. Same shape seen elsewhere: url-vault JSON.parse on index/metadata files without try/catch; waymo-sim waypoint interpolation alpha=(t-t0)/(t1-t0) with no guard for duplicate timestamps. Self-review trigger: any new RegExp(non-literal), JSON.parse(file/network), or division by a data-derived value inside a loop → ask 'does one bad input abort the whole batch?'. Bonus: compile invariant regexes once before the loop, not per-iteration.

### pino logger.X('msg:', err.message) silently drops the error — use logger.X({ err }, 'msg') (2026-07-14)
pino's call signature is logger.LEVEL(mergingObject?, message, ...interpolationValues). When the first arg is a STRING, it is the message and any following args are treated as %s interpolation values. So logger.error('Failed to post:', err.message) has no %s placeholder and pino SILENTLY DISCARDS err.message — the log line shows only the label with zero error detail. This hid the reason for 17 different failure sites across a Discord bot repo's error-handling and logging modules, and made error.log look empty. Correct form: logger.error({ err: err.message }, 'Failed to post') — or pass the whole Error as { err } with a pino err serializer to also keep the stack. Grep for this anti-pattern: logger\.(error|warn|info)\('[^']*', with a following err/.message arg.

### A timeout that releases a lock/semaphore must also drain what was waiting on it (2026-07-16)
When code enforces a cap on an unbounded wait (a per-thread/per-resource lock held forever behind a wedged job), the natural first fix is "release the lock after N minutes so the next caller isn't stuck forever." That's necessary but not sufficient: anything that queued up *behind* the lock while it was held (a job queue, a pending-follow-up list) is still sitting there and gets silently stranded — the release just lets a NEW acquire succeed, it doesn't wake or clear the backlog. Real case: a Discord bot's per-thread capacity wait polled indefinitely on a `_threadLocks` map; a 5-minute deadline was added to release the lock and notify the user, but the naive version left anything queued in the thread's follow-up queue stuck forever (caught by a `reviewer` agent pass before merge, not by the author). Fix shipped together: on timeout, release the lock AND drain/clear the associated queue (plus clear any stale UI state like reactions) so nothing is left waiting on a resource that already gave up on it. Self-review trigger: any timeout/cap added to a lock, mutex, or semaphore-like wait — ask "what else was queued behind this, and does my release path clear it too?"
