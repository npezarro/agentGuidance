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
| `logger.error('Failed to post:', err.message)` (pino) | pino's first-arg-is-string path treats the message as a printf format — the second arg is an interpolation value (no `%s` placeholder → silently discarded). Error detail is lost. | `logger.error({ err: err.message }, 'Failed to post')` — pass data as a merging object in the first arg. For full stacks: `logger.error({ err }, 'msg')` with a pino serializer. Grep: `logger\.(error\|warn)\('[^']*', [a-z]` |
| SQLite `datetime('now')` string → `new Date()` | SQLite stores UTC as `"YYYY-MM-DD HH:MM:SS"` (space-separated, no `T`, no `Z`). ECMAScript's Date parser treats non-ISO forms as **local** time → every stored timestamp shifts by the viewer's UTC offset at render time. | Normalize before parsing: detect `^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$` and rewrite to `${date}T${time}Z`; pass through ISO strings unchanged. |

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

### Centralize query-param parsing; a hand-rolled parseInt without a NaN fallback reaches the DB layer (2026-07-17)
When an API route and its SSR page component both parse the same user-controlled query param (e.g. `?page=`), they will eventually drift. Real case: a route's shared `paginate()` helper had `parseInt(x) || 1` (NaN-safe), but an SSR page hand-rolled `Math.max(1, parseInt(String(x||'1')))` without the `|| 1` fallback. `parseInt('abc')` is `NaN`, `Math.max(1, NaN)` is `NaN`, and `skip = (NaN - 1) * perPage` reached Prisma's `findMany({ skip })` as `NaN`, 500ing on any non-numeric `?page=` value (including whitespace). Fix: extract ONE shared parsing helper and import it everywhere the param is consumed — API routes and SSR pages alike — so the sanitization can't diverge. Self-review trigger: any user-controlled value flowing into a DB query's `skip`/`take`/`where`/limit argument — confirm it's guarded against `NaN`/non-finite before it reaches the query, not just at one of the call sites.

### Re-encoding a payload without updating its declared Content-Type corrupts downstream consumers (2026-07-24)
At every code path that re-encodes a payload to a new format (`buffer = await reEncode(buffer)`), update the accompanying `mimeType`/`Content-Type` variable in the SAME scope in lockstep — never just the buffer.

Real case (manchu-translator PR #21, 2026-07-24): `enhanceImage()` always re-encodes to PNG, but the enhance branch updated the buffer while leaving `mimeType` at the original upload type (e.g. `image/jpeg`). A sibling branch (resize) had the same re-encode and DID update `mimeType = 'image/png'` — divergent handling of the same invariant across sibling branches is the tell. A local worker derived the temp-file extension from the label (`.jpg`), wrote PNG bytes to it, and Claude's Read tool interpreted the file by extension, corrupting the OCR pass.

**Self-review trigger:** any branch that assigns `buffer = await someReEncode(buffer)` without a paired `mimeType = 'new/type'` in the same scope, or any sibling branches where one updates the media type and another doesn't.

**Defense-in-depth (consumer side):** sniff magic bytes (`89 50 4E 47` = PNG, `FF D8 FF` = JPEG, `52 49 46 46…57 45 42 50` = WebP) rather than trusting a caller-supplied Content-Type or file extension. Applies to any image/file pipeline that re-encodes then forwards a declared type.

### A CLAUDE.md Citing Specific Commit Hashes as "Already Fixed" Can Describe Work That Never Merged (2026-07-25)
`collector/edgar.py`'s `_sec_get()` was silently weaker than its repo's CLAUDE.md documented: the doc cited two commits as having built 5-retry exponential backoff plus HTTP 429 handling, but those commits lived only on a `claude/learnings-*`-style branch that was **never merged into the default branch**. A later, independent fix branched off the older pre-fix version of the file (unaware the doc's claimed fix wasn't actually there) and reimplemented retry logic from scratch — landing a weaker version (2 retries, flat delay, no 429 handling) on the default branch. This caused a real production failure: a transient DNS outage exceeded the weak retry budget and dropped a full poll cycle's fetches.

**Rule:** when a CLAUDE.md, gotcha doc, or memory file cites specific commit hashes as the source of a fix, verify those commits are actually ancestors of the branch you're building on before trusting the documented behavior is what's running: `git merge-base --is-ancestor <hash> HEAD` (exit 0 = yes). Automated fix sessions that branch off a feature/PR branch that never gets merged create silent doc/reality drift — a subsequent fixer can then regress a fix that was "already done" on paper. It's also worth periodically diffing the default branch against open or stale `claude/*`/`gemini/*` branches for orphaned reliability/retry work before re-deriving it from scratch.

### Mixed || / ?: precedence silently drops data (2026-07-27)
`a || b ? c : d` parses as `(a || b) ? c : d`, NOT `a || (b ? c : d)`. In an object-literal value this bites when the taken branch can yield null/undefined and a downstream schema/consumer rejects it. Real case (job-scraper lever.js PR #64, run #341): `salary: salary || data.salaryRange ? formatSalaryRange(data.salaryRange) : undefined` evaluated `formatSalaryRange(undefined)` -> null whenever a text-extracted salary existed but the structured range didn't, so `RoleDataSchema.parse` (salary is z.string().optional(), rejects null) threw and the record was silently dropped (listRoles catch->null->filter). Reviewer checklist: (1) any `x || y ? ... : ...` or `x && y ? ... : ...` in a value position is suspect — add parens or split it; (2) enable eslint `no-mixed-operators` and `no-unneeded-ternary` (the repo's eslint did not flag this); (3) a sibling correct form nearby is a strong tell (greenhouse.js used `salary || undefined`; lever was the outlier). Fix pattern: `salary || formatSalaryRange(range) || undefined` — coalesce to undefined so the field is never null.

### SQL LIKE ESCAPE: the escape character must escape itself (2026-07-29)
When a query uses `LIKE ? ESCAPE '\'`, the escaping helper must escape the **escape character itself**, not just the wildcards (`%`, `_`). A lone escape char left in the pattern consumes whatever character follows it. Real case (promptlibrary PR #204, run #343): `escapeLikePattern` only did `input.replace(/[%_]/g, ch => `\\${ch}`)`, three distinct failures reproduced live against `better-sqlite3`:
1. **False negatives** — searching `C:\Users` builds `%C:\Users%`; the unescaped `\U` collapses to `U`, so a row containing `C:\Users\file.txt` returns zero results.
2. **False positives** — searching `\n` builds `%\n%`, which degrades to the bare letter `n` and matches unrelated rows.
3. **Wildcard-injection bypass** — searching `\%` builds `%\\%%` = a literal backslash plus a still-live wildcard. Prefixing a backslash defeats the escaping entirely — the helper is bypassable via the one character it forgot to escape.

Fix: include the escape char in the character class, in a single pass so inserted escapes are never re-scanned: `input.replace(/[\\%_]/g, ch => `\\${ch}`)`. Reviewer checklist: grep any `LIKE ... ESCAPE '<char>'` usage and confirm the accompanying escaping helper's character class contains `<char>` itself. A sibling repo doing it right (groceryGenius `server/lib/escape-like.ts` already escaped `[\\%_]`) while another repo doesn't is the same "divergent sibling" tell as the precedence bug above. Applies to SQLite/Postgres/MySQL `LIKE ESCAPE` and any hand-rolled escaper (shell, regex, CSV) where the escape character is itself legal input.

### Regex classifiers on free-form agent prose need anchored phrase matching, not loose `.*` gaps (2026-07-28)
The Discord bot repo's `errorMonitor.js` classified a manual-approvals channel's messages as merge/deploy failures using `/\*\*.*merge.*fail/i` and `/\*\*.*deploy.*fail/i`. The unbounded `.*` gaps match ANY prose line that contains a bold marker plus "merge"/"deploy" and "fail" anywhere after it — which is exactly how Ecosystem Supervisor proposal text about merging PRs and rule-failure rates reads. 2026-07-28: a supervisor proposal's test-plan line ("**Test plan:** after merge, sample the next 8 ... expect the ... 3-rule failure rate to drop") was auto-classified as a MERGE FAILURE and triggered a bogus deep-investigation, even though the auto-merger was healthy (13d uptime, zero real failures). This is the *second* false-positive class in the same monitor (1st: 2026-07-12, an on-demand PM2 app's healthy on-demand stop matched a "CRASH" pattern). Fix: anchor the failure verb adjacent to merge/deploy so proposal prose can't straddle the gap, and match the monitor's own actual literal failure phrases (`**Merge rejected**`, `**Local merge also failed**`, `**Auto-merge held**`, `**Deploy failed**`, `**Post-deploy ... check FAILED**`) instead of a loose keyword-proximity regex; extracted the match loop into a pure `classifyErrorContent()` function covered by regression tests using the real message text that caused each false positive.

**Rule:** any classifier that runs against free-form agent-generated prose (Discord monitors, log parsers, alert triggers) must match specific literal failure phrases the source actually emits, never a loose `bold-marker + keyword + .* + fail-word` pattern — prose written by another agent about the *topic* of failures (proposals, retros, test plans) will contain the same keywords without describing an actual failure. When writing or reviewing such a classifier, list the exact strings the monitored system emits on real failure and match those, not a keyword co-occurrence heuristic.

### Keyset pagination needs a unique tiebreaker or tied rows drop at page boundaries (2026-07-28)
Keyset/cursor pagination on a NON-UNIQUE sort key (e.g. a `createdAt` timestamp) MUST include a unique tiebreaker column (the PK) in BOTH the `ORDER BY` and the cursor comparison, or rows that tie on the sort key are silently DROPPED at a page boundary. Failure mode: `ORDER BY createdAt DESC` with a strict cursor filter `createdAt < lastCreatedAt` and `nextCursor = lastCreatedAt`. If more rows than the page size share the boundary value S, page 1 shows the page-size subset, `nextCursor = S`, and page 2 (`createdAt < S`) excludes EVERY row at S — the tied rows that never appeared on page 1 are lost forever. Especially sneaky when the column stores whole SECONDS (e.g. SQLite/drizzle `mode:"timestamp"`), making ties common. Real instance: a private social-tooling app's feed endpoint, found via a bug report of reviews silently missing from the feed.

**Fix (keyset):** `ORDER BY sortKey DESC, id DESC` and filter with the tuple predicate `(sortKey < S) OR (sortKey = S AND id < cursorId)`; encode both into the cursor (e.g. `"<S>|<id>"`). `id` is unique so `(sortKey, id)` is a strict total order — no drops, no dupes. Add a discriminating test: N+1 rows sharing one sort-key value at page size N; assert page1 UNION page2 covers all N+1 unique ids.

### Secret-redaction functions miss credentials embedded in URL userinfo (2026-07-22)
Secret-scrubbing functions (shell-history redaction, log sanitizers, chat-log scrubbers) commonly cover env-style assignments (`TOKEN=...`), password flags (`-p`/`--password`), and `Authorization: Bearer` headers, but **miss credentials embedded in a URL's userinfo component**: `scheme://user:secret@host`. Git PAT clone URLs (`https://user:ghp_xxx@github.com/...`), database connection strings (`psql://user:pass@host/db`), and curl basic-auth URLs all carry the secret in the userinfo position and slip through standard scrub patterns.

**Fix:** when writing or auditing any redaction/scrub function, add a userinfo pattern that redacts only the password segment of a `user:secret@` authority:
```js
.replace(/([a-z][a-z0-9+.-]*:\/\/[^/\s:@]+):[^/\s@]+@/gi, '$1:[REDACTED]@')
```
This leaves ordinary URLs (`host:port/path`, `user@host`, scp targets) byte-identical, avoiding over-redaction. Verified in an internal pipeline scrubber (2026-07-22). Sibling scrub functions to audit: session-recall (scrub module), browser-agent (sanitizer), chat-log-export skill.

### Link-liveness checkers: tri-state, fail-open, body-aware — a status code and a `<title>` are both insufficient (2026-07-29)
A cross-repo audit of five independent link/product/job-liveness checkers (shopper `link-verifier.ts`, employ `link-check.ts`, job-pipeline `liveness.py`, and two job-scraper `link-checker.js` copies) found all five were false-flagging live pages as dead, driven by one root cause: bot walls that return a normal-looking HTTP response. Worst offender — Amazon serves its CAPTCHA page as **HTTP 200** with `<title>Amazon.com</title>` (and intermittently a bare 404 for the same live product); neither the code nor the title reveals the block, only the body does. Measured impact in shopper before the fix: 25 of 88 link warnings were live Amazon products mislabeled "possible wrong product," 14 more mislabeled "Dead link - HTTP 404" while returning 200 on re-check. Full detail: `knowledgeBase/patterns/url-liveness-detection.md`.

**Rules for any liveness/dead-link checker:**
1. **Tri-state, not boolean.** `live` / `dead` / `unknown` — a boolean forces every ambiguous case into a wrong answer.
2. **Fail open.** Only flag "dead" on positive confirmation; a missing warning is far cheaper than a false one.
3. **Never treat these as dead:** 401, 403, 408, 429, 451, any 5xx, timeouts, DNS failures — they describe what happened to the *checker*, not the page.
4. **Inspect the response BODY before trusting the status code.** Returning early on `status >= 400` means a bot-block check can never fire on the exact responses that need it.
5. **Send a real browser User-Agent.** An identifiable bot UA (e.g. `JobSearchBot/1.0`) is precisely what triggers the 403/429 in the first place.
6. **Anchor title/text regexes.** A bare `/404/i` matches "Peavey 404 Powered Mixer"; a bare `/robot/i` matches "Robot Vacuum."
7. **A redirect only proves closure when the job/product ID is LOST**, not when the path merely got shorter — locale strips (`/en-us/careers/job/12345` → `/careers/job/12345`) and suffix drops (`/jobs/12345/apply` → `/jobs/12345`) are benign canonicalization.
8. **Never guess an ATS board token from a generic subdomain label.** `careers`/`jobs`/`talent`/etc. are real board tokens on OTHER companies' Greenhouse instances — `boards-api.greenhouse.io/v1/boards/talent` returns 200.
9. **Watch for a shared `AbortController` across a HEAD→GET fallback** — once the timer aborts the HEAD, the GET inherits the already-aborted signal and rejects instantly without touching the network, making the fallback a guaranteed no-op.

### Threading a new field through a multi-verb CLI: grep every command that builds its own payload (2026-08-02)
`browser-cli.sh`'s `focus` and `close` verbs hit the same incomplete-plumbing bug for the **third time**: a shared helper (`split_target` / `target_json`) was extended to accept a chrome tab id in addition to a URL, and the fix reached the `cdp-*` verbs plus `network-capture`/`extract-virtual` — but `focus` and `close` build their own inline JSON (`{"action":"focusTab", url:$u}`) instead of calling the shared helper, so they silently kept the old URL-only behavior. Symptom: a bare chrome tab id sent to `close` matched no tab (`Target tab not found (url match "1832811575")`) and failed silently in the chain-awards collector, leaking a tab after every page.

**Rule:** when threading a new field/capability through a shared helper in a multi-verb CLI or router, `grep` for every verb/command that constructs its own request/action object rather than assuming the shared helper's call sites cover them all. Two prior instances of this exact bug class in the same file (browser-agent `browser-cli.sh`) means "grep for other callers" needs to be a standing step of the change, not a one-off catch. After the fix, re-verify every verb that touches the same conceptual object (not just the one that was reported broken) — the sibling verb here (`close`) had the identical bug and had not yet been reported.
### Check for sibling deliverables before revising a doc another session may have deepened (2026-07-31)
Before extending a deliverable, list the sibling files in its directory and follow every internal link in it. A parallel session may have produced deeper research that CONTRADICTS the doc you are about to extend, and the doc may already carry a superseded-by pointer.

On 2026-08-01, extending a conference prep guide with an itinerary, the guide linked a companion briefing that carried a bold 'Partly superseded' banner pointing at a third doc built from full talk transcripts. That third doc reversed a core recommendation: the target speaker's frame is 'verification', not 'evals' (39 uses vs 0 in a 112-minute workshop), and he is publicly skeptical of evals. The original guide's suggested opening question was eval-framed, i.e. actively wrong. Extending without reading siblings would have shipped a confidently-wrong question into a same-day deliverable.

Procedure before editing any deliverable:
  ls <dir>                                   # siblings the doc may not link
  grep -oE '\]\(\./[^)]+\)' <doc>           # every internal link
  grep -inE 'supersede|correction|stale|outdated|use .* instead' <doc> <siblings>

Then verify each link resolves, since a superseded-by pointer to a missing file is worse than none:
  for f in $(grep -oE '\]\(\./[^)]+\)' doc.md | sed 's/](\.\///; s/)$//'); do [ -e "$f" ] && echo "OK $f" || echo "MISSING $f"; done

### Substring-matching short blocklist tokens silently drops legitimate content (2026-08-03)
A keyword blocklist matched with a bare substring test (`any(w in text for w in WORDS)`, `text.includes(w)`, `LIKE '%w%'`) is wrong the moment ANY entry is short enough to sit inside an ordinary word. The short entry silently matches unrelated text, and if the match feeds a HARD FILTER the affected item is not down-ranked, it DISAPPEARS. Real case (a YouTube shorts automation repo, run #344): PROFANITY_WORDS contained "ass", matched via `any(p in all_text for p in PROFANITY_WORDS)`. Every window containing pass/class/assist/massive/password/grass/assassin/embarrassing/compass/classic was flagged profane; because score_window returns 0 when a flagged window scores under PROFANITY_ENERGY_THRESHOLD, clean gameplay clips were dropped from candidate selection entirely. 12/12 sampled innocent gaming phrases false-positived.

Do NOT 'fix' this by wrapping every entry in \b. That trades false positives for false NEGATIVES: \bfuck\b stops matching 'fucking', \bshit\b stops matching 'shitty'. And prefix-anchoring (\bass\w*) reintroduces the original bug ('assist', 'assassin'). No single uniform rule is correct, because the list mixes long unambiguous tokens with short dangerous ones.

Correct shape: keep substring matching as the DEFAULT (it catches inflections for free), and maintain an explicit whole-word exception set for the short entries, then enumerate the compound forms in the main list:
    WHOLE_WORD = {"ass", "asses"}          # \b-anchored
    WORDS = [..., "asshole", "dumbass", "badass"]  # substring, unambiguous
    parts = [rf'\b{re.escape(w)}\b' if w in WHOLE_WORD else re.escape(w) for w in WORDS]
    PATTERN = re.compile('|'.join(parts))

Reviewer checklist: (1) for every blocklist/keyword filter, ask 'is any entry <= 4 chars, and is it a substring of a common word?' — grep the entry against a word list; (2) trace whether a match causes a hard drop (return 0 / continue / filter out) rather than a score adjustment — hard drops make the bug invisible, since the dropped item leaves no log line; (3) when you add \b anchors, ALWAYS re-test the inflections the old substring form used to catch, in BOTH directions (innocent-must-be-clean AND profane-must-still-match) — a one-directional test suite will happily certify a recall regression; (4) verify escape/anchor interaction for non-alphabetic entries (censor markers like "***" or "[__]") — \b does not apply where there are no word characters at the edges.

The compound list is an OPEN CLASS and any enumeration of it is incomplete by construction. Budget for that: document it as incomplete, and do NOT claim "so nothing is lost". In the run that produced this entry the first attempt shipped exactly that claim with a three-item allowlist {asshole, dumbass, badass}; an independent verifier then diffed old-matcher vs new-matcher over 131 strings and found 22 recall losses (jackass, smartass, asswipe, half-assed, fatass, kickass ...). Because the match fed a hard gate, the losses did not merely mislabel: low-energy windows that used to be gated to 0 now scored ~7.4 and became SELECTABLE. Trading a false-positive bug for a false-negative bug of the same size is not a fix.

Two process lessons, both cheap:
  - Write the recall test in the SAME commit as the anchor change, enumerating the strings the old form caught. The original test suite was one-directional (innocent-must-be-clean) and happily certified the regression green.
  - For any matching change, mechanically diff old vs new over a few hundred strings drawn from BOTH classes, rather than reasoning about which cases changed. The 22 losses were invisible to inspection and obvious to a diff.

Related: this is the same family as pattern-like-escape-char-must-self-escape (matching-layer helper that looks right in isolation but is wrong against the real matcher semantics).
