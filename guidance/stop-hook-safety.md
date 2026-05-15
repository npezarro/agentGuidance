# Stop Hook Safety

Stop hooks fire on every Claude CLI session exit, including pipe-mode (`-p`) sessions spawned by autonomous scripts, subagents, and other hooks. This makes them powerful for enforcement but dangerous for recursion.

## Tier Classification

Every stop hook falls into one of three tiers based on its risk profile:

### Tier 1: Observation (fire-and-forget)
- Token tracking, tray notifications, logging
- No Claude invocation, no blocking
- Timeout: 5-15s
- Risk: effectively zero
- Examples: `token-tracker`, `claude-tray-hook`

### Tier 2: Verification (can block, no Claude)
- Deploy health checks, unpushed code gates
- Can return `{"decision":"block"}` to keep the session alive
- No Claude invocation, so no recursion risk
- Timeout: 15-30s
- Risk: can delay session exit, but can't loop
- Examples: `verify-deploy.sh`, `check-unpushed.sh`

### Tier 3: Claude-invoking (DANGEROUS)
- Session scoring, analysis, any LLM-powered post-processing
- **Can create infinite recursion** if not properly guarded
- Must use all mandatory safeguards below
- Timeout: 60s max for the Claude subprocess
- Must run in background (never block session exit)
- Examples: `score-session.sh`

## Mandatory Safeguards for Tier 3 Hooks

Use the shared guard library (`hooks/lib/stop-hook-guard.sh`) which provides all of these automatically:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib/stop-hook-guard.sh"
stop_hook_init "my-hook-name" --invokes-claude

# HOOK_INPUT, SESSION_ID, TRANSCRIPT are now available
# All guards have passed if execution reaches here
```

### What the guard library provides:

1. **Env var circuit breaker** — Exports `CLAUDE_HOOK_<NAME>=1` before invoking Claude. Checks it at entry and exits if set. Prevents the hook from firing on sessions it spawned.

2. **Lockfile** — PID-based lockfile in `/tmp/claude-hook-locks/`. Prevents concurrent execution of the same hook. Auto-cleaned via trap.

3. **Rate limiter** — Per-hook invocation counter in `/tmp/claude-hook-rates/`. Default: max 5 invocations per hour. Pruned automatically.

### Additional safeguards the hook author must implement:

4. **Content fingerprinting** — Grep the conversation for the hook's own prompt signature. The env var guard can fail if the shell doesn't inherit env vars; this is the fallback.

```bash
CONVERSATION=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty')
if printf '%s' "$CONVERSATION" | grep -q 'my unique prompt marker'; then
  exit 0
fi
```

5. **Minimum conversation length** — Skip trivial sessions (quick Q&A, accidental exits). A 200-char minimum is a good default.

6. **Background execution** — The Claude invocation must run in background so the hook doesn't block session exit:

```bash
(
  timeout 60 claude -p --dangerously-skip-permissions --no-chrome \
    --model haiku "..." < "$TMPFILE" 2>/dev/null
  rm -f "$TMPFILE"
) &
exit 0
```

7. **Subprocess timeout** — Always wrap `claude -p` in `timeout 60` (or similar). A hung Claude session should not persist indefinitely.

## Template: Tier 3 Hook

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib/stop-hook-guard.sh"
stop_hook_init "my-analysis" --invokes-claude

# Content fingerprint fallback
LAST_MSG=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty')
if printf '%s' "$LAST_MSG" | grep -q 'MY_UNIQUE_MARKER'; then
  exit 0
fi

# Skip trivial sessions
[ "${#LAST_MSG}" -lt 200 ] && exit 0

# Prepare input
TMPFILE=$(mktemp /tmp/hook-analysis-XXXXXX.txt)
printf '%s' "$LAST_MSG" | tail -c 5000 > "$TMPFILE"

# Fire and forget
(
  timeout 60 claude -p --dangerously-skip-permissions --no-chrome \
    --model haiku "Analyze this session: ..." < "$TMPFILE" 2>/dev/null
  rm -f "$TMPFILE"
) &

exit 0
```

## Rules for All Tiers

1. **Always `exit 0` at the end.** A non-zero exit from a stop hook can abort session teardown.
2. **Never retry on failure.** Hooks are fire-and-forget. Log the failure and move on.
3. **Timeouts are mandatory.** Use the `timeout` field in settings.json AND `timeout` command for subprocesses.
4. **No interactive prompts.** Stop hooks run without a TTY. Any `read` or interactive Claude session will hang.
5. **Redact before transmitting.** Any hook that sends conversation content externally must strip credentials (see `post-closeout.sh` for the redaction pattern).

## Debugging Hook Issues

Check these in order:
1. Rate log: `cat /tmp/claude-hook-rates/<hook-name>.log`
2. Lock state: `ls -la /tmp/claude-hook-locks/`
3. Env var: `env | grep CLAUDE_HOOK`
4. Token usage: `~/.claude-token-tracker/usage.jsonl` for clusters of sessions

## Adding a New Stop Hook Checklist

Before adding any new Stop hook to settings.json:

- [ ] Classified into Tier 1, 2, or 3
- [ ] Timeout set in settings.json (`"timeout"` field)
- [ ] Ends with `exit 0`
- [ ] If Tier 3: uses `stop-hook-guard.sh` with `--invokes-claude`
- [ ] If Tier 3: has content fingerprint fallback
- [ ] If Tier 3: runs Claude in background with `timeout`
- [ ] If Tier 3: has minimum conversation length check
- [ ] If Tier 2 (blocking): block reason is actionable (tells the agent what to fix)
- [ ] Tested manually: `echo '{"session_id":"test","transcript_path":""}' | bash hooks/my-hook.sh`
