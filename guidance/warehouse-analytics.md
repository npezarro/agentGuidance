# Warehouse Analytics

Pipeline for analyzing large cloud-warehouse datasets (Snowflake, BigQuery): **connect → cost-aware extract → local DuckDB analysis → publish**. Big data stays in the warehouse and local parquet; only small aggregates and reports reach git/Sheets/Docs.

Interactive sessions: use the `warehouse-analytics` skill (`~/.claude/skills/warehouse-analytics/`) — it has the full procedure + runnable reference scripts. This file exists so autonomous agents get the non-obvious gotchas without loading the skill.

## Gotchas (each cost a real debugging cycle)
- **Snowflake auth ladder:** password is blocked when MFA is enforced. Use a PAT (programmatic access token) — but it requires a network policy on the account/user first, and it is bound to a specific user (often a dedicated service user; "token invalid" usually means the username doesn't match). Key-pair is the alternative and needs no network policy.
- **Cost gate:** never launch a multi-hour/100s-of-GB pull blind. Sample one slice, measure rows/sec + bytes/row, extrapolate, and show the estimate before committing.
- **DuckDB on parquet:** free local analysis, no warehouse cost. Reserved words `offset`/`rows` can't be bare aliases; `DATE - BIGINT` needs an INTEGER cast; quoted mixed-case warehouse columns need `"Quotes"`.
- **Retention censoring:** separate time-boxed measures (D1/D7, day-0 rates — comparable across cohorts) from cumulative lifetime metrics (active-days, payer% — biased for recent cohorts). State which.
- **Publish traps:** GitHub blocks files >100MB (shard parquet; never commit raw/PII); rclone `--drive-import-formats csv` makes an xlsx blob not a native Sheet (use the Drive API / Sheets MCP); the Google Docs MCP renders no markdown (insert clean text, then apply native styles/links).
- **rclone OAuth in WSL:** open the `127.0.0.1:53682` link in the Windows browser (WSL2 shares localhost); `pkill -f "rclone authorize"` self-kills the launching shell (use `pkill -x rclone`); don't pipe authorize to `head` (SIGPIPE kills the listener); click through Google's "unverified app" screen.
- **Game platform entity key ambiguity (PlayFab):** PlayFab event schemas use different `Entity_Id` namespaces — `title_player_account` for session/entity events and `master_player_account` for classic gameplay events. Keying players on `Entity_Id` double-counts every human and manufactures false "never played" cohorts. Always key on `EntityLineage_master_player_account` (non-null ~99.6%). Discovered via a PlayFab 302GB extract where this produced a fictitious "52% never play" headline (actual: ~5%). The same multi-tier entity pattern likely applies to other live-service game analytics platforms.

Example implementation: `~/repos/analytics` + `~/repos/SuperAnimalRoyalDataAnalysis`. Closeout: privateContext/deliverables/closeouts/2026-06-23-snowflake-playfab-analytics.md
