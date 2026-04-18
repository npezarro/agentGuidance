# Testing Guidance

Detailed testing standards that extend the core rules in `agent.md`.

## When to Test

| Situation | Action |
|-----------|--------|
| Bug fix | Write a regression test that fails without the fix, passes with it |
| New function with logic | Unit test covering happy path + edge cases |
| API endpoint | Integration test covering request/response cycle |
| Refactor | Ensure existing tests still pass; add tests if coverage was lacking |
| Config/copy-only change | No new tests needed |
| Repo has no test infra | Don't add one unless asked |

## Test File Placement

- Match the repo's existing pattern. Common conventions:
  - `__tests__/ComponentName.test.js` (React/Jest)
  - `tests/test_module.py` (Python/pytest)
  - `*.spec.ts` next to the source file (Vitest, Mocha)
- If no convention exists, co-locate tests next to source files.

## Test Structure

```javascript
describe('functionName', () => {
  it('returns expected result for valid input', () => {
    // Arrange
    const input = 'valid';

    // Act
    const result = functionName(input);

    // Assert
    expect(result).toBe('expected');
  });

  it('throws on invalid input', () => {
    expect(() => functionName(null)).toThrow();
  });
});
```

## What to Test

- **Happy path:** Does the function work with typical input?
- **Edge cases:** Empty strings, zero, null/undefined, large numbers, special characters.
- **Error paths:** Does it fail gracefully with bad input?
- **Boundaries:** Off-by-one errors, array boundaries, date rollovers.

## What NOT to Test

- Implementation details (private methods, internal state).
- Third-party library behavior (trust that `lodash.get` works).
- Trivial getters/setters with no logic.
- UI layout pixel-by-pixel (use snapshot tests sparingly).

## Mocking Guidelines

- **Mock at boundaries:** HTTP clients, databases, file system, timers, `Date.now()`.
- **Don't mock the unit under test.** If you need to, the function is doing too much — refactor it.
- **Prefer dependency injection** over module-level mocking where possible.
- **Reset mocks between tests:** `beforeEach(() => jest.clearAllMocks())` or equivalent.
- **Use typed mock helpers instead of `as any`:** Create factory functions that return complete typed objects rather than casting partial objects. This catches shape mismatches at compile time and eliminates lint warnings.

```typescript
// WRONG — hides type errors, triggers no-explicit-any lint warnings
const token = { access_token: "test" } as any;

// RIGHT — typed factory returns a complete object
function fakeOAuthToken(overrides?: Partial<OAuthToken>): OAuthToken {
  return { access_token: "test", refresh_token: "r", expires_at: Date.now() + 3600000, ...overrides };
}
const token = fakeOAuthToken();
```

## Test Fixture Schema Drift

When tests embed their own DDL (CREATE TABLE) or data shapes, they silently drift from the real schema as the application evolves. Tests pass against the stale fixture schema while production uses the real one.

**Signs:** Tests pass locally but the feature is broken in prod, or a batch of tests fail simultaneously after a migration adds columns.

**Prevention:**
- Import schema definitions from the application code rather than duplicating them in tests
- If tests must define their own schema (e.g., SQLite in-memory), derive it from the same migration files the application uses
- When adding a column or field to the real schema, search test files for the table name and update inline definitions

## Runtime Version Compatibility

Local dev environments often run newer runtime versions than CI. Using APIs only available in newer versions causes tests to pass locally but fail in CI.

**Node.js:** Local is v22+, most CI workflows pin Node 20. Avoid these Node 22+ APIs in application and test code:
- `Promise.withResolvers()` — use manual `new Promise((resolve, reject) => ...)` instead
- `Object.groupBy()` / `Map.groupBy()` — use a reduce-based helper or lodash
- `import.meta.resolve()` without flag — not stable until Node 22

**Python:** Local is 3.12, but some CI matrices test 3.10/3.11. Avoid 3.11+ features when the CI matrix includes older versions:
- `ExceptionGroup` / `except*` (3.11+)
- `tomllib` (3.11+ stdlib, use `tomli` package for 3.10)

**How to check:** Before using a newer API, check the repo's `.github/workflows/*.yml` for the `node-version` or `python-version` field. If CI targets an older version, use a compatible alternative.

## Running Tests

```bash
# JavaScript/TypeScript
npm test                    # run full suite
npx jest --watch            # watch mode during development
npx jest path/to/test.js    # run a single test file
npx jest --coverage         # check coverage

# Python
pytest                      # run full suite
pytest tests/test_file.py   # single file
pytest -x                   # stop on first failure
pytest --cov=src            # check coverage
```

## Coverage

- Don't chase 100% coverage. Aim for meaningful coverage of business logic.
- Uncovered code is fine if it's glue code, config, or error handling that's hard to trigger in tests.
- If the repo has a coverage threshold configured, respect it.

## Testing Pyramid Strategy

When a project has recurring quality issues (code ships that doesn't actually work), apply this prioritized testing investment. Each layer reduces the number of incidents the next layer needs to catch.

| Priority | Layer | What It Catches | Cost |
|----------|-------|-----------------|------|
| 1 | Failure audit | Tells you where to invest | Hours |
| 2 | Contract tests | Mock drift, API shape mismatches | Low |
| 3 | Integration tests (real deps) | Backend logic, migrations, auth bugs | Medium |
| 4 | Post-deploy smoke tests | Config drift, bad deploys | Low |
| 5 | Authenticated browser tests | Auth flows, full-stack integration | High |

**Start at the top.** Do not skip to browser tests without completing the lower layers first.

### Layer 1: Failure Audit

Before writing any new tests, classify the last 5-10 production incidents. For each:
- What broke (auth, rendering, data, config, race condition)
- Whether a test existed for that path
- If a test existed and passed, *why* it passed when prod was broken (mock drift, shallow assertion, wrong environment config)
- When it was caught (pre-deploy, post-deploy, user report)

Use `templates/failure-audit.md` to structure this. The output tells you exactly which testing layer to invest in.

### Layer 2: Contract Tests

If incidents trace back to "test passed with mocks but prod behaved differently," your mocks encode stale assumptions. Fix this with:
- Schema checks against real API responses recorded from staging
- Snapshot the actual response shape from a real endpoint, then validate mocks match that shape
- Update snapshots as part of the deploy pipeline

**When to use:** Any service boundary where you currently use mocks -- external APIs, database queries, auth providers.

### Layer 3: Integration Tests with Real Dependencies

For backend logic failures (bad queries, broken migrations, auth provider interactions):
- Hit real databases, real auth providers, and real caches
- Control state setup explicitly -- each test owns its fixtures
- Run in CI, deterministic if you own the fixture lifecycle
- **Do not mock the database** -- mock/prod divergence is the #1 source of false-green tests

### Layer 4: Post-Deploy Smoke Tests

Lightweight, fast (under 30 seconds), non-browser checks against the deployed environment:
- Authenticate with a test account
- Hit the 3-5 most critical endpoints
- Assert HTTP 200 and basic response shape (not just status code)
- Run automatically after every staging deploy

This catches environment config drift and bad deploys immediately. It is deployment validation, not e2e testing.

### Layer 5: Authenticated Browser Tests (Use Sparingly)

Only proceed here if the failure audit shows incidents that ONLY a real browser would have caught (broken auth flows, CORS/CSP issues, token refresh failures).

**Constraints:**
- Maximum 5-8 scenarios. Start by reproducing a specific past incident, not writing speculative tests
- Dedicated test account with stable credentials, managed via secrets
- Run against staging only, never production
- Each test owns its state -- setup creates what it needs, teardown removes it
- Assert on intercepted API responses, not just DOM elements
- Capture screenshots, network logs, and console errors on failure

**Flakiness policy:** Quarantine on the second consecutive flake. Move to a non-blocking suite until fixed. A flaky test the team ignores is worse than no test.

**Tag every test** by the failure mode it guards against (`@auth-flow`, `@regression-INCIDENT-42`).

## Mock Fidelity

Mocks that diverge from production are worse than no mocks -- they give false confidence.

- **Record real responses** from staging/production as mock fixtures. Re-record periodically
- **Validate mock shape** against the real API schema on every CI run
- **Never hand-write mock data** for external APIs -- use recorded fixtures
- **If a mock test passes but the feature is broken in prod**, the mock is the bug -- fix the mock, not the test

## Cross-Layer Invariant Tests

The highest-value tests are often not about individual functions — they're about **invariants between layers** that silently break when one layer changes without updating the other.

### What Are Invariants?

An invariant is a property that must hold for the system to work, even though no single function enforces it. Examples:

| Invariant | Producer | Consumer | What Breaks |
|-----------|----------|----------|-------------|
| Stores must have lat/lng | Pipeline creates stores | Trip planner filters by `storesWithCoords` | Pipeline creates stores without coords → trip planner returns 0 plans |
| Price records must include unit | Pipeline ingests prices | UI formats as `$2.99/lb` | Missing unit → UI shows `$2.99` with no context |
| Shopping list items serialize to JSON | Frontend `setItems()` | Backend PATCH `/api/shopping-lists/:id` | Shape mismatch → silent data loss on save |
| API response includes store name | Backend joins tables | Frontend sparkline display | Missing join → UI shows price with no store attribution |

### When to Write Invariant Tests

Write an invariant test whenever:
1. **You just fixed a cross-layer bug.** The fix goes in the code; the invariant test goes in the test suite. This is the regression test for the *class of bug*, not just the specific instance.
2. **One system produces data another consumes.** Pipeline → database → API → UI. Each boundary is an invariant.
3. **A filter or query depends on data shape.** If `WHERE lat IS NOT NULL` is used anywhere, test that the data producer always sets lat.
4. **Display formatting depends on API response shape.** If the UI expects `storeName` in the response, test that the API actually returns it.

### How to Write Them

Invariant tests don't need a database. Test the **contract** — the shape and constraints of data flowing between layers:

```typescript
describe("Pipeline → Trip Planner invariant", () => {
  it("pipeline-created stores must have coordinates", () => {
    // This is the shape the pipeline produces
    const store = createPipelineStore("kroger", "94102");
    // This is the filter the trip planner applies
    const visible = [store].filter(s => s.lat != null && s.lng != null);
    expect(visible).toHaveLength(1); // Would have caught the bug
  });
});

describe("API → UI invariant", () => {
  it("price history response includes storeName and unit", () => {
    const response = buildPriceHistoryResponse(priceRecord);
    expect(response).toHaveProperty("storeName");
    expect(response).toHaveProperty("unit");
  });
});
```

### Naming Convention

Name invariant tests after the boundary they guard:
- `pipeline-stores.test.ts` — pipeline → database shape
- `price-display.test.ts` — API response → UI formatting
- `trip-planner.test.ts` — database query assumptions

### Common Patterns Across Projects

These invariants recur in every full-stack project:

1. **Geocoding completeness:** Any entity with lat/lng that gets filtered by location queries must have coordinates populated at creation time.
2. **API response shape:** If the frontend destructures `response.storeName`, the backend must include it in the SELECT/JOIN.
3. **Serialization roundtrip:** Data written to localStorage/database must survive JSON.parse(JSON.stringify(data)) without losing fields.
4. **Auth-gated endpoints:** Every endpoint behind `requireAuth` must return 401 for unauthenticated requests, not 500.
5. **Unit/format consistency:** If prices are stored as strings (`"2.99"`) but displayed as numbers (`2.99`), test the parseFloat boundary.

## Zod Validation in API Routes

Every Next.js API route that parses input with Zod **must** catch `ZodError` and return a 400 response. Without this, Zod validation failures bubble up as unhandled exceptions → 500 Internal Server Error, which hides the real problem from the client.

```typescript
import { ZodError } from "zod";

try {
  const data = mySchema.parse(await req.json());
  // ... handle request
} catch (error) {
  if (error instanceof ZodError) {
    return NextResponse.json(
      { error: "Validation failed", details: error.errors },
      { status: 400 }
    );
  }
  throw error; // re-throw non-validation errors
}
```

**When adding a new Zod-validated endpoint**, always include the ZodError catch. When auditing an existing codebase, check that *every* route using `.parse()` has this handling — it's easy to miss one (groceryGenius had this exact gap on a single endpoint while all others were correct).

## Live Browser Testing via Browser Agent

For testing web apps in a real browser during development, use the **browser-agent** system. This is a Tampermonkey userscript + relay server + CLI that lets Claude send commands to the user's live Edge browser and get results synchronously.

**When to use:** Integration testing, debugging UI issues, verifying deployed changes, form fill testing, or any scenario where you need to see what the user's real browser shows.

**Quick start:**
```bash
browser-cli tabs                          # check a tab is connected
browser-cli navigate "http://localhost:3000"
browser-cli state                         # read page: buttons, inputs, errors
browser-cli click "Submit"                # interact
browser-cli assert-text "Success"         # verify
browser-cli console                       # check for errors
```

**Key detail:** All commands are synchronous (send + block for result). See `privateContext/infrastructure.md` for the full command reference and architecture details.

**Prefer this over Playwright/headless** for testing on the user's machine — it runs in the real browser with real cookies/session, bypasses CAPTCHA, and tests exactly what the user sees.

## What NOT to Build

- Browser tests against production (test data leaks into real systems)
- More than 8-10 browser test scenarios (you're compensating for missing integration tests -- push coverage down the pyramid)
- Tests without a corresponding past incident (speculative tests have low ROI and high maintenance cost)
