# PM Experience Log

---
## 2026-03-31 | botlink MVP scope
**Task:** Define the MVP scope for BotLink's public launch, distinguishing must-haves from nice-to-haves.
**What worked:** Used the "if we launched tomorrow, what would embarrass us?" test to cut scope. Must-haves: bot registration, public profile page, search/discovery, basic capability tags. Deferred: integration verification (checking if a bot's claimed integrations actually work), analytics dashboard, API access for programmatic registration. Each deferred item got a one-line rationale so the decision could be revisited without relitigating from scratch.
**What didn't:** Initially included "social features" (following bots, activity feed) in the MVP because they seemed easy to build. Challenged this by asking "how many users do we need before follows are useful?" The answer was hundreds; the MVP would have tens. Cut it and saved two weeks of development.
**Learned:** Features that require network effects (follows, feeds, recommendations) should never be in an MVP. They provide zero value at low user counts and distract from the core value proposition. Defer social features until the product has proven its core utility with enough users to make the social layer meaningful.

---
## 2026-03-24 | groceryGenius success metrics
**Task:** Define success metrics for the recipe import feature to determine if it should be expanded or sunset.
**What worked:** Defined three tiers of metrics: (1) usage (imports per week, unique importers), (2) quality (successful parse rate, user edits after import), (3) retention (do importers come back within 7 days?). The "user edits after import" metric was the key quality signal: high edit rates meant the parser was producing low-quality output that users had to fix manually. Set the decision threshold at 60% parse success rate for continued investment.
**What didn't:** Initially proposed tracking only "number of imports" as the success metric. This would have missed the quality dimension entirely: a feature that is used frequently but produces garbage output is not successful. The edit-rate metric caught this distinction.
**Learned:** Usage metrics alone are misleading for data-processing features. A feature can have high usage and low value if the output requires heavy manual correction. Always pair a usage metric with a quality metric that measures how much the user has to fix the output. The ratio of automated-to-manual effort is the true success indicator.

---
## 2026-03-19 | auto-dev scope and guardrails
**Task:** Define the scope and safety guardrails for the autonomous dev agent that runs unattended via cron.
**What worked:** Framed the scope as "fix-only, never feature": the agent should fix lint errors, failing tests, and small bugs, but never add new functionality or refactor code. This constraint made the risk assessment tractable: the worst case is a bad fix (revertible), not an unwanted feature (harder to remove). Added a protected repos list (discord-bot, agentGuidance, auto-dev) that the agent cannot touch.
**What didn't:** Initially scoped the agent to "improve code quality" which was too vague: it could justify anything from renaming variables to rewriting modules. Narrowing to "fix" made the acceptance criteria testable: did the fix resolve the specific error? Did it introduce new errors?
**Learned:** For autonomous agents, scope must be defined as a closed set of permitted actions, not an open-ended goal. "Improve code quality" is an open-ended goal that resists evaluation. "Fix lint errors and failing tests" is a closed set with clear success criteria. Autonomous systems need tighter scope definitions than human-driven work because there is no judgment call at execution time.
