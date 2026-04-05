# Testing Experience Log

---
## 2026-04-02 | runeval test architecture
**Task:** Design the test suite structure for runeval's eval runner, covering unit tests for scoring logic and integration tests for the API layer.
**What worked:** Separated tests by level: `__tests__/unit/` for pure scoring functions (deterministic, no I/O), `__tests__/integration/` for API endpoints (hits a test database, verifies full request/response cycle). Used Jest's `--projects` config to run them with different settings (unit tests use jsdom, integration tests use node environment with a test database URL).
**What didn't:** Initially mocked the database in integration tests using jest.mock, which made the tests pass but missed a real bug: a Prisma query that used a field name that did not exist in the actual schema. The mock accepted any field name. Switched to a real test database and the bug surfaced immediately.
**Learned:** Integration tests that mock the database defeat their own purpose. The value of an integration test is exercising the real data path. Use a real test database (SQLite in-memory for simple cases, a containerized PostgreSQL for schema-dependent cases). Mock only external services you do not control (third-party APIs), never your own database.

---
## 2026-03-28 | groceryGenius recipe parser tests
**Task:** Write tests for the recipe URL parser that handles diverse HTML structures across recipe sites.
**What worked:** Fixture-based testing: saved real HTML responses from 10 recipe sites as local files, then wrote tests that parse each fixture and assert on the extracted fields (title, ingredients, instructions). This made tests deterministic (no network calls) and documented the parser's actual capability across sites. When a new site format failed, adding its HTML as a fixture and a failing test made the gap explicit.
**What didn't:** Tried snapshot testing initially (parse HTML, snapshot the full output object). The snapshots were 200+ lines each and broke on every minor parser improvement, even when the improvement was correct. Switched to targeted assertions on specific fields, which survived parser refactors.
**Learned:** Snapshot tests are a poor fit for parsers with evolving output. Every improvement to the parser breaks snapshots, creating a "boy who cried wolf" effect where developers auto-update snapshots without reading them. Use targeted assertions on the specific fields that matter. Fixture-based testing with real-world inputs is more valuable than synthetic test HTML.

---
## 2026-03-22 | discord-bot command handler tests
**Task:** Add test coverage for the Discord bot's command dispatch and individual command handlers.
**What worked:** Mocked the Discord.js Client and Message objects with factory functions that produce realistic-looking objects with configurable properties (author, channel, content, guild). Each command handler test follows the pattern: create message -> call handler -> assert on reply content and side effects. The factory approach made it easy to test permission variations (admin vs regular user, DM vs guild).
**What didn't:** Tried using Discord.js's own types to construct test messages, but the constructors require a live Client instance with a valid token. Building test messages from plain objects with the right shape was simpler and did not require connecting to Discord.
**Learned:** For libraries with complex constructors that require live connections (Discord.js, Mongoose, Prisma Client), build test doubles from plain objects that match the shape you consume, not from the library's own constructors. You are testing your code's behavior, not the library's construction logic. Factory functions that return typed plain objects are the right abstraction.

---
## 2026-03-18 | activity-tracker collector isolation tests
**Task:** Write tests verifying that each data collector (Strava, Garmin) can start, collect, and stop independently without affecting other collectors.
**What worked:** Each collector test runs in isolation: start the collector, trigger a collection cycle with mocked API responses, verify the collected data, then stop. Used Jest's `beforeEach` to reset the collector state. The key assertion was that starting/stopping one collector did not affect the state or scheduled timers of another collector.
**What didn't:** Initially ran all collector tests in a single describe block with shared setup. A timing issue in the Strava collector's interval caused it to fire during the Garmin test, producing intermittent failures. Separating each collector into its own describe block with independent setup/teardown fixed the flakiness.
**Learned:** Tests for timer-based or interval-based code must ensure complete isolation of timers between test cases. Shared describe blocks with beforeAll create subtle timer leakage. Use beforeEach/afterEach with explicit timer cleanup (clearInterval, jest.useRealTimers) in every test case, not just at the suite level.
