# Data Experience Log

---
## 2026-04-03 | activity-tracker instrumentation
**Task:** Design structured logging for the activity-tracker's collector modules to enable debugging stalled collectors and measuring collection latency.
**What worked:** Consistent JSON log schema across all collectors: { collector, event, duration_ms, items_collected, status, error }. Adding a heartbeat metric (last_successful_collection timestamp per collector) made it trivial to detect stalled collectors without parsing log files.
**What didn't:** Initially logged every individual item collected, which produced thousands of log lines per collection cycle. The signal-to-noise ratio was terrible. Switched to aggregate logging (count per cycle) with item-level detail only on errors.
**Learned:** Log at the right granularity for the question you are trying to answer. Per-item logging answers "what happened to item X" but buries "is the system healthy" under noise. Start with aggregate metrics for health monitoring, add item-level detail only in error paths or behind a debug flag.

---
## 2026-03-26 | runeval metrics dashboard
**Task:** Design the data model and dashboard layout for tracking eval run results over time, including pass rates, latency distributions, and regression detection.
**What worked:** Storing raw eval results in append-only rows with (run_id, eval_name, metric_name, metric_value, timestamp) made it easy to compute aggregates at query time. The dashboard followed the SLI-first pattern: top row shows pass rate trend and p95 latency, drill-down panels show per-eval breakdowns.
**What didn't:** Tried building a pre-aggregated summary table that updated on each run. The aggregation logic became complex when handling partial runs (some evals skipped) and re-runs (same eval, same day, different config). Dropped it in favor of query-time aggregation.
**Learned:** For small datasets (under 100K rows), query-time aggregation is simpler and more flexible than pre-aggregated tables. Pre-aggregation introduces complexity around partial data, re-runs, and schema changes. Only invest in materialized views when query latency becomes a user-facing problem.

---
## 2026-03-19 | autonomousDev operational telemetry
**Task:** Add observability to the autonomous dev agent's cron execution so failures, token usage, and task completion rates are trackable over time.
**What worked:** Structured the telemetry around three questions: "did it run?" (cron heartbeat), "did it succeed?" (exit code + task status), "how much did it cost?" (token count per run). Writing a single JSON line per run to an append-only log file kept the implementation simple.
**What didn't:** Tried shipping metrics to a local SQLite database but the overhead of maintaining the schema, handling migrations, and writing queries was not justified for a single cron job. The append-only JSON log was sufficient.
**Learned:** Match the observability infrastructure to the system's scale. A single cron job does not need a time-series database. An append-only JSON log with jq covers most debugging and trend questions. Invest in structured storage only when you need cross-system correlation or alerting.
