# Failure Audit — [Project Name]

> Classify the last 5-10 production incidents before investing in new testing infrastructure.
> Copy this template, fill it out, then use the Priority Matrix to decide where to invest.

## Audit Date
YYYY-MM-DD

## Incidents

| # | Date | What Broke | Category | Test Existed? | Why Test Passed | Caught By | Time to Fix |
|---|------|------------|----------|---------------|-----------------|-----------|-------------|
| 1 | | | auth / rendering / data / config / race / deploy | yes / no | mock drift / shallow assert / wrong env / N/A | pre-deploy / post-deploy / user report | |
| 2 | | | | | | | |
| 3 | | | | | | | |
| 4 | | | | | | | |
| 5 | | | | | | | |

## Category Counts

| Category | Count | Incidents |
|----------|-------|-----------|
| Auth | | |
| Rendering | | |
| Data / DB | | |
| Config / Env | | |
| Race condition | | |
| Deploy | | |

## Root Cause Patterns

| Pattern | Count | Fix |
|---------|-------|-----|
| Mock passed, prod failed | | Contract tests (Layer 2) |
| No test existed for the path | | Integration tests (Layer 3) |
| Test existed but was too shallow | | Deeper assertions |
| Environment config mismatch | | Post-deploy smoke tests (Layer 4) |
| Only visible in a real browser | | Browser tests (Layer 5) |

## Priority Matrix

Based on the counts above, invest in this order:
1. **Highest count category** -- fix this first
2. **Most common root cause pattern** -- apply the corresponding fix from the table above
3. **Longest time-to-fix incidents** -- automate detection for these

## Action Items
- [ ] ...
