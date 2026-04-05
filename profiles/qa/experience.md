# QA Experience Log

---
## 2026-04-01 | groceryGenius recipe import flow
**Task:** Walk through the recipe import user journey end-to-end, testing happy path, error states, and edge cases.
**What worked:** Tested with real URLs from 10 different recipe sites (not just the 3 the developer used). Found that 4 of 10 returned empty ingredients because those sites use client-side rendering. Also tested: invalid URLs (got a generic 500 instead of a helpful 400), extremely long URLs (accepted but caused a timeout), and duplicate imports (created duplicate records with no dedup). Each finding categorized by user impact, not technical severity.
**What didn't:** Initially focused on the API response format, checking JSON structure and status codes. Missed the actual user experience: the UI showed a generic "import failed" message with no guidance on what to try next. The API was returning useful error details that the frontend was not displaying.
**Learned:** QA for data import features must test with real-world inputs from diverse sources, not just the developer's test set. Recipe sites vary wildly in HTML structure, rendering approach, and bot protection. Also: always test the full stack (UI + API), not just the API. A correct API response that the UI swallows is still a user-facing bug.

---
## 2026-03-26 | pezantTools file upload edge cases
**Task:** Test the file upload flow for boundary conditions: zero-byte files, very large files, special characters in filenames, concurrent uploads.
**What worked:** Found three issues: (1) zero-byte files were accepted and created empty records in the database, (2) filenames with spaces were URL-encoded in storage but not decoded on download, producing "%20" in downloaded filenames, (3) uploading the same filename twice overwrote the first file without warning. Verified each fix by retesting the specific scenario.
**What didn't:** Tried to automate all edge case tests as Jest integration tests, but the file upload endpoint required multipart form data construction that was fragile in the test environment. Ended up with a mix of automated tests for validation logic and manual tests for the upload flow itself.
**Learned:** Not every QA scenario needs to be automated. File upload edge cases (encoding, concurrent access, large files) are often more reliably tested manually or with a dedicated tool (Postman, curl scripts) than with unit test frameworks that mock the HTTP layer. Automate the validation logic; manually test the I/O behavior.

---
## 2026-03-20 | runeval staging vs production parity
**Task:** Verify that the staging environment matches production for runeval before a major deployment.
**What worked:** Built a checklist: Node version (matched), npm dependencies (staging had 3 outdated packages), environment variables (staging was missing 2 new vars added in the latest PR), database schema (staging was one migration behind). Fixed all four discrepancies before deploying. The database migration gap would have caused a runtime crash on the new API endpoint.
**What didn't:** Initially assumed staging was up-to-date because the last deploy was recent. The "recent deploy" had been to production only; staging was 2 weeks stale. Should have checked timestamps, not assumptions.
**Learned:** Never assume environment parity from recency. Always verify explicitly: check dependency versions, env vars, database schema version, and config files before deploying. A staging environment that is "mostly" in sync is worse than one that is obviously stale, because "mostly" hides the specific discrepancy that will cause the production failure.
