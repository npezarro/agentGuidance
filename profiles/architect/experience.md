# Architect Experience Log

---
## 2026-03-24 | centralDiscord command routing
**Task:** Evaluate whether the Discord bot's command dispatch should use middleware chains or flat dispatch tables.
**What worked:** Flat dispatch table with a simple registry object. The bot has ~20 commands, not 200. A middleware chain added complexity (ordering dependencies, error propagation) without solving a real problem.
**What didn't:** Initially sketched a middleware pattern inspired by Express. Abandoned it when the mapping between HTTP middleware and Discord command routing broke down -- Discord commands don't have the same linear request/response flow.
**Learned:** Match the pattern to the problem's actual shape, not to a familiar analogy from a different domain. Flat dispatch beats middleware when the routing space is small and commands are independent.

---
## 2026-03-23 | promptlibrary Next.js architecture
**Task:** Review the promptlibrary Next.js app architecture -- users reported slow page loads and difficulty adding features.
**What worked:** Identified three root causes: (1) waterfall data fetching from nested server components, (2) client-side Context providers causing full-tree re-renders, (3) file-per-concern organization forcing 5+ file changes per feature. Recommended parallel data fetching with Promise.all, server state via React cache() instead of Context, and feature-based module folders.
**What didn't:** Initially suggested React Server Components streaming, but the app uses next-auth session checks in layouts that block streaming anyway. Had to adjust to work within that constraint.
**Learned:** In Next.js apps, auth session checks in layouts are the most common streaming blocker. Always check the auth middleware/layout pattern before recommending streaming architecture.

---
## 2026-03-22 | groceryGenius database schema
**Task:** Design the schema extension for recipe sharing (multi-user access to recipe lists).
**What worked:** Junction table approach (user_recipe_shares) with role column (owner/editor/viewer). Kept the existing recipes table untouched, added the sharing layer alongside it. Migration was additive-only, no breaking changes.
**What didn't:** Considered embedding sharing permissions as a JSON column on recipes. Rejected it because querying "all recipes shared with user X" would require scanning every row.
**Learned:** For access control, always prefer relational modeling (junction tables) over JSON columns. The query patterns for "who has access to what" and "what can this user access" both need indexed lookups.

---
## 2026-03-21 | activity-tracker module boundaries
**Task:** Review the activity-tracker's supervisor/collector/summarizer architecture for testability.
**What worked:** The supervisor pattern (one entry point that starts/stops collectors) is clean. Each collector is independent with a start/stop/getStats interface. The summarizer runs on its own timer. This made it possible to test each module in isolation.
**What didn't:** The supervisor imports collectors at the top level and calls main() on import, which makes the module hard to test without mock.module(). A factory function returning the supervisor would have been more testable.
**Learned:** Modules that execute on import (side-effect imports) are an anti-pattern for testability. Prefer exporting factory functions or init() methods that the caller invokes explicitly.

---
## 2026-03-20 | pezantTools upload security review
**Task:** Architecture review of the upload admin page for XSS vulnerabilities.
**What worked:** Traced the full data flow: API response -> JavaScript -> DOM. Found that innerHTML was used to render both server-validated data (project names) and unvalidated data (error messages). The fix was switching to programmatic DOM construction (createElement/textContent) everywhere.
**What didn't:** Initially only focused on the project list rendering. Missed that showMessage() also used innerHTML until a second pass through the code. The lesson is to grep for all innerHTML/insertAdjacentHTML calls, not just the ones in the obvious render path.
**Learned:** When reviewing for injection vulnerabilities, search for the sink pattern (innerHTML, eval, document.write) across the entire file, not just the function you're looking at. Vulnerabilities cluster -- if one function uses innerHTML, adjacent functions probably do too.

---
## 2026-03-19 | valueSortify state management
**Task:** Evaluate whether valueSortify's phase-based state machine (sorting -> ranking -> results) should use a state management library.
**What worked:** Kept it as React useState with phase enum. The app has 3 phases with clear transitions. Adding Redux or Zustand would triple the boilerplate for no architectural benefit at this scale.
**What didn't:** Briefly explored useReducer for the phase transitions, but the transitions are simple enough (setPhase('ranking')) that a reducer just adds indirection.
**Learned:** State management libraries earn their keep when you have shared state across many components or complex derived state. A linear phase machine with local state in a single parent component doesn't need one.

---
## 2026-03-18 | botlink Prisma schema design
**Task:** Review BotLink's database schema -- Prisma with PostgreSQL, modeling AI bot profiles with capabilities, integrations, and professional identity.
**What worked:** The schema uses a clean entity hierarchy: Bot -> BotCapability, Bot -> BotIntegration, Bot -> BotExperience. Each relationship table has its own lifecycle and can be queried independently.
**What didn't:** The Bot model has 15 fields including several optional JSON columns (metadata, config). Suggested splitting the rarely-accessed fields into a BotProfile extension table, but the team decided the query simplicity of a single table outweighed the storage concern at their current scale (~500 bots).
**Learned:** For early-stage products with small datasets, a wider table with optional columns is often better than normalized extension tables. The join overhead and code complexity of split tables isn't worth it until the table has 10K+ rows or the optional columns are large blobs.
