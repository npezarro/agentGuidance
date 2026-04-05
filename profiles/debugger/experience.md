# Debugger Experience Log

---
## 2026-04-03 | centralDiscord command handler crash
**Task:** Diagnose why the Discord bot silently dropped messages containing certain emoji sequences without logging any error.
**What worked:** Reproduced the issue by sending the exact emoji sequence from the bug report. The stack trace showed a TypeError in the message parser where a regex split on emoji boundaries produced empty string elements. Traced the root cause to a filter step that assumed all split results were non-empty.
**What didn't:** Initially suspected a Discord API rate limit or websocket disconnect because the symptom was "bot ignores messages." Spent time checking connection logs before realizing the bot was receiving the messages fine but crashing silently in the handler.
**Learned:** When a bot "ignores" messages, check the handler error logs before the connection logs. Silent crashes in message handlers (especially with unhandled promise rejections) look identical to network issues from the user's perspective. Always reproduce with the exact input first.

---
## 2026-03-30 | groceryGenius ingredient parser failures
**Task:** Investigate why certain recipe URLs produced empty ingredient lists despite the page clearly showing ingredients.
**What worked:** Compared the page's rendered DOM against the raw HTML response. The ingredients were loaded via client-side JavaScript after initial page load, so the server-side parser found nothing. Confirmed by curling the page and diffing against the rendered source.
**What didn't:** Initially suspected a CSS selector mismatch and spent time testing different selector patterns against the static HTML. The selectors were correct; the content simply was not present in the initial response.
**Learned:** When a parser returns empty results, verify the content exists in the raw response before debugging the parser logic. Client-side rendered content is invisible to server-side HTML parsers. Always diff the raw HTTP response against the browser-rendered DOM as the first diagnostic step for scraping issues.

---
## 2026-03-24 | pezantTools deployment script failure
**Task:** Root-cause a deployment script that succeeded locally but failed on the GCP VM with "EACCES: permission denied" on a config file write.
**What worked:** Compared file ownership and permissions between local and VM environments. The deployment script ran as the deploy user but the config directory was owned by root (created during initial server setup). Used `ls -la` and `id` to confirm the mismatch systematically.
**What didn't:** Initially suspected an SELinux or AppArmor restriction and searched for security module logs. The VM did not have either enabled. Checking basic file permissions should have been step one.
**Learned:** For "works locally, fails on server" permission errors, check the basics in order: (1) which user is the process running as, (2) who owns the file/directory, (3) what are the permission bits. Only investigate security modules after ruling out basic ownership mismatches.

---
## 2026-03-18 | promptlibrary search results inconsistency
**Task:** Debug why the prompt library search returned different results for the same query when run seconds apart.
**What worked:** Added timestamps to search query logs and discovered the issue was a stale in-memory cache with a 60-second TTL, but the underlying data was being updated every 10 seconds by another process. Used git log to confirm the cache was added recently as a performance optimization.
**What didn't:** Tried to reproduce by running the same search repeatedly in a loop, which did not trigger the issue because the cache was consistent within a single refresh cycle. Only reproduced it by modifying the underlying data between searches.
**Learned:** Non-deterministic behavior that depends on timing requires reproducing the exact interleaving, not just the operation. For cache-related bugs, the reproduction must include both the read pattern and the write pattern that causes staleness. Always check git history to see if caching was recently added when debugging inconsistent results.
