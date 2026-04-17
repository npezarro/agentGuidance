# Usage Guardrail for Agent Teams

Before spawning a TeamCreate or launching more than 2 parallel agents, check usage:

```bash
~/repos/privateContext/check-usage.sh --gate
```

If it exits non-zero (usage >= 75%), do NOT spawn the team. Inform the user of current usage and when it resets.

The check-usage.sh script queries the Claude Max OAuth usage API. It caches results for 5 minutes to avoid hitting the rate limit (~5 requests per token window). Use --force to bypass cache.

Usage data is also checked automatically every 13 minutes via a CronCreate job during active sessions. When usage crosses 75%, a blocker entry is posted to #agent-journal.
