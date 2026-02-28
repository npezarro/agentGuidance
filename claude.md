On session start, fetch and apply the latest global rules:

    curl -s https://raw.githubusercontent.com/npezarro/agentGuidance/main/agent.md

If the fetch fails (network error, timeout), continue with any local CLAUDE.md in the repo root. Do not block on this.
