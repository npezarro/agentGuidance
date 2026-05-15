# Reviewer Experience Log

---
## 2026-04-03 | agentGuidance hook scripts
**Task:** Review the post-to-discord.sh and post-to-wordpress.sh hook scripts for security, correctness, and maintainability.
**What worked:** Systematic review order: (1) security (secrets handling, injection risk in curl commands, variable quoting), (2) correctness (error handling, exit codes, edge cases), (3) maintainability (naming, comments, structure). Found that the Discord webhook URL was interpolated directly into a curl -d JSON string, creating a JSON injection risk if the message content contained double quotes. Fixed by using jq for JSON construction instead of string interpolation.
**What didn't:** Initially focused on shellcheck warnings (unused variables, unquoted expansions) before checking the security-critical paths. The shellcheck findings were all minor; the JSON injection risk was critical but not caught by shellcheck. Should have prioritized security review over lint findings.
**Learned:** For shell scripts that handle user-controlled input and call external APIs, review security first (injection, secrets exposure), then correctness, then style. Linting tools like shellcheck catch syntax issues but miss semantic security problems. Any script that constructs JSON or SQL from variables must use a structured builder (jq for JSON, parameterized queries for SQL), never string concatenation.

---
## 2026-03-31 | auto-dev fix-checker
**Task:** Review the autonomous dev agent's fix-checker module for safety, correctness, and potential runaway behavior.
**What worked:** Identified three critical safety gaps: (1) no timeout on individual fix attempts, meaning a stuck Claude CLI call would block the entire run indefinitely, (2) no validation that the fix actually resolved the original error (it committed and pushed without re-running the failing test), (3) the branch naming used predictable patterns that could collide if two runs targeted the same repo simultaneously.
**What didn't:** Spent time reviewing code style and naming conventions before checking the safety properties. For autonomous code that runs unattended, safety review must come first because the blast radius of a safety bug is much larger than a naming inconsistency.
**Learned:** For autonomous/unattended code, prioritize review categories differently than for human-operated code: (1) safety and blast radius (timeouts, resource limits, rollback), (2) correctness (does it verify its own work?), (3) idempotency (can it run twice without damage?). Style and naming are last priority. A well-named function that runs forever without a timeout is worse than a poorly-named one with proper resource limits.

---
## 2026-03-25 | pezantTools API routes
**Task:** Review PR adding new admin API routes for file management (list, delete, rename) in pezantTools.
**What worked:** Caught an authorization gap: the admin middleware checked for a valid session but did not verify the user had admin role. Any authenticated user could delete files. Also found that the delete endpoint used `fs.unlinkSync` without checking if the file path was within the uploads directory, creating a path traversal vulnerability (../../etc/passwd).
**What didn't:** The PR description said "admin routes" so initially trusted that auth was handled. Reading the actual middleware code revealed the gap. Lesson reinforced: never trust PR descriptions; read the implementation.
**Learned:** File operation endpoints are high-risk for two categories of bugs: (1) authorization (who can call this?), and (2) path traversal (can the caller escape the intended directory?). Always check both when reviewing file management APIs. Use path.resolve and verify the resolved path starts with the expected base directory before any fs operation.

---
## 2026-03-20 | botlink Prisma schema and API
**Task:** Review the initial BotLink codebase: Prisma schema, API routes, and authentication flow.
**What worked:** Reviewed in dependency order: schema first (data model correctness), then API routes (do they match the schema?), then auth (is access properly gated?). Found that the Bot model's `capabilities` field was a JSON column storing an untyped array, meaning the API could accept any shape. Recommended adding a Zod schema for runtime validation to complement Prisma's storage-level types.
**What didn't:** Tried reviewing all routes simultaneously, jumping between files. Lost track of which routes had auth middleware and which did not. Switched to reviewing one resource at a time (all bot routes, then all user routes) which made gaps more visible.
**Learned:** Review API codebases one resource at a time, not one file at a time. Checking all routes for "bots" together makes it obvious when one route is missing auth middleware that all the others have. File-by-file review scatters related routes across multiple passes and makes inconsistencies harder to spot.

---
## 2026-05-15 | agentGuidance batch PR review
**Task:** Review 6 learning-agent PRs for merge readiness: correctness, secrets, duplicates, append-only compliance.
**What worked:** Fetched all 6 diffs in parallel, then verified claims against live state (crontab for cron frequency, hooks/ listing for renamed script). Caught that #208 and #206 were near-duplicates modifying the same file and line, with #206 being strictly better (includes rationale paragraph). Flagged a residual line from #208 not covered by #206 as a follow-up action item.
**What didn't:** Nothing significant -- parallel diff fetching and metadata retrieval kept the review fast.
**Learned:** When reviewing batches of auto-generated PRs (learning agent output), always verify factual claims against live system state (crontab, filesystem, git log). Duplicate detection requires comparing not just titles but exact lines touched and diff content. When recommending one duplicate over another, check if the rejected PR has any unique additions worth preserving as follow-ups.

---
## 2026-05-15 | agentGuidance batch PR review (5 PRs: #213-#217)
**Task:** Review 5 learning-agent PRs for merge readiness: secrets scan, factual correctness, append-only compliance, duplicate detection.
**What worked:** Fetched all 5 diffs in parallel, then ran targeted checks: verified --no-chrome is a real CLI flag, confirmed JSON.stringify(Infinity) behavior, validated Next.js redirect+basePath auto-prepend semantics. Scanned all diffs for credential patterns (passwords, API keys, IPs, SSH keys) -- all clean. Detected that 3 PRs (#213, #214, #215) all insert rows at the same line in code-review.md, which creates a merge-order dependency.
**What didn't:** Nothing significant -- the parallel approach kept review time low.
**Learned:** When multiple PRs touch the same table or list at the same insertion point, flag the merge-order dependency explicitly. The content of each may be correct independently, but merging them requires sequential rebase. Also: security experience log entries that discuss audit findings (mentioning "secret", "token", "API key") will trip automated secret scanners -- read them in context to distinguish discussion-of-secrets from actual-secrets before flagging.

---
## 2026-05-15 | agentGuidance PR batch #197-#205
**Task:** Review 9 PRs for merge readiness: secrets, factual correctness, duplicates, append-only compliance.
**What worked:** Fetched all 9 diffs in parallel, then read the current state of every modified file to check for duplicates and context. Verified the Node 20 EOL claim (April 30, 2026) via nodejs.org. Compared #199 and #204 side-by-side since both added npm overrides to the same file; identified #204 as the more complete version and #199 as having one unique pattern ($devDep reference syntax) worth preserving after rebase. Also caught a corrupted UTF-8 character in #199's diff on an existing line.
**What didn't:** Could have checked research-quality.md earlier to confirm deep-research.md was complementary rather than overlapping; ended up reading it after forming an initial opinion.
**Learned:** When two PRs modify the same file at the same location, compare both diffs side-by-side before recommending merge order. The more complete PR should merge first; the other should rebase and contribute only its unique additions. Also: always verify factual date claims (EOL dates, deprecation timelines) against primary sources rather than trusting PR authors.
