# Reviewer Experience Log

---
## 2026-04-03 | agentGuidance hook scripts
**Task:** Review the post-to-discord.sh and post-to-wordpress.sh hook scripts for security, correctness, and maintainability.
**What worked:** Systematic review order: (1) security (secrets handling, injection risk in curl commands, variable quoting), (2) correctness (error handling, exit codes, edge cases), (3) maintainability (naming, comments, structure). Found that the Discord webhook URL was interpolated directly into a curl -d JSON string, creating a JSON injection risk if the message content contained double quotes. Fixed by using jq for JSON construction instead of string interpolation.
**What didn't:** Initially focused on shellcheck warnings (unused variables, unquoted expansions) before checking the security-critical paths. The shellcheck findings were all minor; the JSON injection risk was critical but not caught by shellcheck. Should have prioritized security review over lint findings.
**Learned:** For shell scripts that handle user-controlled input and call external APIs, review security first (injection, secrets exposure), then correctness, then style. Linting tools like shellcheck catch syntax issues but miss semantic security problems. Any script that constructs JSON or SQL from variables must use a structured builder (jq for JSON, parameterized queries for SQL), never string concatenation.

---
## 2026-03-31 | autonomousDev fix-checker
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
