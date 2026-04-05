# Implementer Experience Log

---
## 2026-04-01 | discord-bot scheduled task system
**Task:** Assess the feasibility of adding a scheduled task system (cron-like) to the Discord bot for recurring automation (daily summaries, periodic health checks).
**What worked:** Mapped the data flow end-to-end: task definition (stored in a JSON config file) -> scheduler (node-cron library, runs in the bot process) -> executor (calls the same command handlers used by Discord commands) -> reporter (posts results to a designated channel). Reusing existing command handlers meant zero new business logic; the scheduler was just a new trigger mechanism.
**What didn't:** Initially evaluated building a separate microservice for scheduling to avoid coupling the scheduler lifecycle to the bot process. Abandoned it because the bot already runs 24/7 via PM2, and adding a second long-running process doubled the operational surface (two things to monitor, two things that can crash) for no isolation benefit at this scale.
**Learned:** Before proposing a new service, check if an existing long-running process can host the new functionality. Adding a scheduler to a bot that already runs 24/7 is simpler than deploying a separate scheduler service. The operational overhead of a second process (monitoring, restarts, log management) only pays off when the workloads have genuinely different scaling or reliability requirements.

---
## 2026-03-25 | runeval parallel test execution
**Task:** Evaluate whether runeval's sequential eval runner could be parallelized to reduce wall-clock time.
**What worked:** Identified the critical path: evals were independent (no shared state between runs) but the runner processed them sequentially because the original author used a for-of loop with await. Replaced with Promise.allSettled with a concurrency limit (p-limit, max 3) to parallelize without overwhelming the API. Wall-clock time dropped from 12 minutes to 4 minutes for a 20-eval suite.
**What didn't:** First attempt used Promise.all without a concurrency limit, which fired all 20 eval API calls simultaneously. The API returned 429 (rate limit) on about half of them. Adding p-limit with a conservative concurrency of 3 fixed the rate limiting without requiring retry logic.
**Learned:** When parallelizing API-dependent work, always use a concurrency limiter (p-limit or similar). Promise.all without limits converts a serial bottleneck into a rate-limit bottleneck. Start with a conservative concurrency (3-5) and increase based on observed rate limits, not theoretical throughput.

---
## 2026-03-20 | activity-tracker Garmin data pipeline
**Task:** Assess the implementation complexity of adding Garmin health data (sleep, heart rate, body battery) to the activity tracker alongside existing Strava data.
**What worked:** Traced the existing Strava pipeline to identify reusable abstractions: the collector interface (start/stop/getStats), the data normalization layer, and the storage adapter. The Garmin collector could implement the same interface, meaning the summarizer and dashboard would work without changes. Identified that the Garmin API uses push webhooks (not polling like Strava), which meant a new webhook endpoint but no scheduler changes.
**What didn't:** Estimated the webhook endpoint as a "simple Express route" without accounting for Garmin's signature verification requirement and the fact that webhook payloads contain activity IDs, not activity data (requiring a second API call to fetch details). The actual implementation was 3x the initial estimate.
**Learned:** When estimating API integration work, always read the full API documentation for the specific endpoints you will use, not just the overview. Webhook-based APIs have hidden complexity: signature verification, payload-vs-reference patterns (do you get the data or just a pointer?), retry policies, and ordering guarantees. Each of these adds implementation work that a surface-level assessment misses.
