# Critic Experience Log

---
## 2026-04-01 | botlink launch readiness review
**Task:** Adversarial review of BotLink's launch plan, looking for failure modes in the bot registration flow and profile discovery system.
**What worked:** Identified three critical gaps: (1) no rate limiting on bot registration, allowing a single actor to flood the directory with spam profiles, (2) the "featured bots" algorithm had no decay function, so early registrants would dominate the listing permanently, (3) the profile completeness score counted optional fields equally, incentivizing users to fill garbage data rather than meaningful content.
**What didn't:** Initially focused on infrastructure failure modes (database overload, API timeouts) which were already well-handled. The real risks were behavioral, not technical. Wasted time modeling traffic projections before realizing the threat was quality degradation, not volume.
**Learned:** For marketplace/directory products, the most dangerous failure modes are behavioral (spam, gaming, stale content), not infrastructural. Shift adversarial analysis toward "how will bad actors exploit this" and "what perverse incentives does this design create" before analyzing load and uptime scenarios.

---
## 2026-03-25 | auto-dev cron safety
**Task:** Review the autonomous dev agent's cron-based execution model for failure modes and uncontrolled behavior.
**What worked:** Found the critical single point of failure: the agent reads its task list from a local JSON file with no locking mechanism. If the cron job fires while a previous run is still writing to the file, the task list corrupts silently. Also identified that the agent had no spending cap or token budget, meaning a stuck loop could burn through API credits indefinitely without any circuit breaker.
**What didn't:** Tried to model complex multi-agent race conditions before checking the basics. The single-writer corruption issue was far more likely and more dangerous than the exotic concurrency scenarios. Should have started with the simplest failure mode first.
**Learned:** When reviewing autonomous systems, check the mundane failure modes first: file locking, process overlap, resource exhaustion, missing circuit breakers. Exotic failure scenarios make for interesting analysis but rarely cause the actual outages. The most dangerous autonomous system failure is the one that runs silently and accumulates cost.

---
## 2026-03-20 | discord-bot command permission model
**Task:** Challenge the proposed permission system for Discord bot commands (role-based with channel overrides).
**What worked:** Identified that the channel override system created a hidden complexity cost: debugging "why can't user X run command Y in channel Z" required checking three layers (global role, channel override, command-specific flag). Proposed a simpler two-layer model (role grants, explicit denies) that covered 95% of use cases. Also flagged that the permission cache had no TTL, so role changes would not take effect until bot restart.
**What didn't:** Pushed initially for a full RBAC system with permission inheritance, which was massive overkill for a bot with ~20 commands and ~50 users. The team correctly pushed back, and the simpler two-layer model was the right call.
**Learned:** Permission systems have a hidden maintenance cost that scales with their complexity, not their feature set. Every additional layer of override or inheritance is a layer of "why doesn't this work" debugging. For small user bases, prefer flat permission models with explicit deny lists over hierarchical inheritance.
