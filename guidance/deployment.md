# Deployment

## Pre-Deploy Checklist

1. All changes committed and pushed via PR.
2. Build succeeds locally.
3. Tests pass.
4. `context.md` updated with deployment intent.
5. No secrets exposed in repository history.
6. Dependencies are locked (`package-lock.json` committed).
7. **If `package.json` or `package-lock.json` changed, run `npm install` on the target before restarting.** Missing this causes crash loops from missing modules.

## Post-Deploy Verification

"It built clean" is not "it works." Run these within 30 seconds of every deploy:

1. `pm2 show <process>` to confirm status is `online`, uptime is climbing, restart count hasn't spiked.
2. `curl -s -o /dev/null -w "%{http_code}" <url>` to confirm HTTP 200 from the live URL.
3. `pm2 logs <process> --lines 20` to scan for errors, uncaught exceptions, or crash loops in the first 30 seconds.
4. If the app has authentication, verify the sign-in flow works end-to-end.
5. **Test the actual user-facing behavior yourself** before asking the user to verify. Use the browser agent for interactive pages, `curl` for APIs, or direct tool invocation. Never declare "done, try it out" without verifying it works.
6. Update `context.md` with deployment status and any issues observed.
7. If any check fails, **do not move on**. Diagnose and fix before declaring the deploy complete.

Infer deploy commands from repo config (GitHub Actions, scripts, `context.md`).

## Python Version Compatibility

The GCP VM runs **Python 3.9**. Modern type annotation syntax (`X | None`, `list[str]`, `dict[str, Any]`) requires Python 3.10+. Code using these features will raise `TypeError` at runtime on the VM.

**Fix:** Add `from __future__ import annotations` at the top of every Python file that uses modern type syntax. This makes all annotations strings (evaluated lazily), avoiding the runtime error on 3.9.

This caused 3 failed PRs on llm-tasks (2026-04-05) before the root cause was identified. Always test Python code against 3.9 syntax rules before deploying to the VM.

## Check the Server Before Asking

When you're missing information about production — env vars, configs, logs, database state, file paths, what's running — SSH into the VM and look it up rather than asking the user. The VM is a live, authoritative source. Check `.env` files, PM2 configs, Apache configs, logs, and file structure. Also check `~/repos/privateContext/` locally for credentials and reference files. See `privateContext/infrastructure.md` for access details.

**Why:** The user treats the VM and local machine as a unified environment. Asking for information that's already discoverable wastes time.

## Apache WebSocket Proxy

When adding a WebSocket service behind Apache on the VM:

1. **ProxyPass rules MUST be inside `<VirtualHost>`** — appending after `</VirtualHost>` causes silent 404s with no error in logs.
2. **Use `ProxyPass ws://`**, not `RewriteRule`, for WebSocket upgrade handling.
3. **Add the `QSA` flag** if the client passes query strings (e.g., API keys as `?key=...`).

```apache
# Inside <VirtualHost *:443>
ProxyPass /api/my-service/ws ws://127.0.0.1:PORT/
ProxyPass /api/my-service/ http://127.0.0.1:PORT/
ProxyPassReverse /api/my-service/ http://127.0.0.1:PORT/
```

**Why:** The phone-agent deploy (2026-04-10) hit this exact issue — WS proxy rules appended outside the VirtualHost block caused 404s that were hard to diagnose. This applies to any WS service: browser-agent, phone-agent, pm-interview, etc.

## VM SSH Access

The GCP VM username is **not** the same as the local username. Before SSH-ing or writing paths that reference the home directory, check `privateContext/sensitive-identifiers.md` for the correct username — hardcoding the wrong one is a recurring source of deploy failures. Always use `$HOME` or `~` in scripts rather than hardcoded paths like `/home/<user>/`.
