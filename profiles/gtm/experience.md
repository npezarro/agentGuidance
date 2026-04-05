# GTM Experience Log

---
## 2026-03-30 | botlink beta launch plan
**Task:** Design the rollout plan for BotLink's public beta, including staged access, feedback collection, and success metrics.
**What worked:** Three-stage rollout: (1) private alpha with 5 hand-picked bot developers for qualitative feedback, (2) open beta with a waitlist for controlled onboarding, (3) public launch after addressing alpha/beta feedback. Defined three success gates between stages: registration completion rate > 80%, at least 3 bots with complete profiles, zero critical bugs in 48 hours.
**What didn't:** Initially planned a single "big bang" launch announcement. Realized that without staged access, there would be no feedback loop before public exposure. The first 50 users' experience would define the product's reputation, so controlling who those users were mattered.
**Learned:** For developer-facing products, the first users are not just users; they are co-designers. Stage the rollout so early adopters' feedback can be incorporated before the public sees the product. Define quantitative gates between stages (not just "it feels ready") to prevent premature promotion.

---
## 2026-03-24 | groceryGenius recipe sharing feature flag
**Task:** Plan the feature flag strategy for rolling out recipe sharing (multi-user access to recipe lists) without breaking existing single-user workflows.
**What worked:** Used a simple boolean flag in the user's profile record (not a separate feature flag service) since the user base was small. The flag controlled UI visibility only; the API endpoints were always available but required explicit sharing permissions. This meant the API could be tested independently of the UI rollout.
**What didn't:** Considered using a third-party feature flag service (LaunchDarkly, Flagsmith) but the overhead of adding a dependency, configuring the SDK, and managing the dashboard was not justified for a single flag on a small user base. A database column was simpler and sufficient.
**Learned:** Match feature flag infrastructure to the scale of the product. A database boolean covers single-feature rollouts for small user bases. Invest in a feature flag service only when you have multiple flags, percentage rollouts, or A/B testing needs. The simplest implementation that meets the requirement is the right one.

---
## 2026-03-19 | pezantTools file upload migration guide
**Task:** Write the migration guide for the new chunked upload API, documenting the breaking changes from the old single-request upload.
**What worked:** Structured the guide as before/after code examples: old API call on the left, new API call on the right. Included a migration script that detected old-format uploads in the database and flagged them for re-upload. Added a deprecation warning to the old endpoint that returned the migration guide URL in the response headers.
**What didn't:** Initially wrote a prose-heavy migration document that explained the architectural rationale. Users skipped the explanation and could not find the actual code changes. Rewrote it as a step-by-step checklist with code snippets.
**Learned:** Migration guides should be code-first, not explanation-first. Lead with before/after examples and a numbered checklist. Put architectural rationale in a collapsible section or appendix. Users reading migration guides want "what do I change" not "why did you change it."
