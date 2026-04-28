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

## Automated Deploy Enforcement (Hooks)

Two hooks mechanically enforce post-deploy verification, even if the agent skips the manual checklist above:

1. **`hooks/track-deploy.sh`** (PostToolUse on Bash): Detects `pm2 restart/start/reload` commands and records the deployed service name to a per-session tracker file. Also detects SSH deploy patterns (`ssh ... pm2 restart`). Uses `privateContext/deploy-registry.json` to map PM2 names to services.

2. **`hooks/verify-deploy.sh`** (Stop hook): When a session ends, reads the tracker and curls each deployed service's health endpoint and user-facing URLs from the registry. **Blocks the session exit** if any check fails, forcing the agent to diagnose and fix before stopping.

**Why this exists:** The #1 failure mode was agents deploying, declaring "done," and leaving without testing. The Stop hook makes this structurally impossible for registered services.

## Python Version Compatibility

The GCP VM runs **Python 3.9**. Modern type annotation syntax (`X | None`, `list[str]`, `dict[str, Any]`) requires Python 3.10+. Code using these features will raise `TypeError` at runtime on the VM.

**Fix:** Add `from __future__ import annotations` at the top of every Python file that uses modern type syntax. This makes all annotations strings (evaluated lazily), avoiding the runtime error on 3.9.

This caused 3 failed PRs on llm-tasks (2026-04-05) before the root cause was identified. Always test Python code against 3.9 syntax rules before deploying to the VM.

## Check the Server Before Asking

When you're missing information about production — env vars, configs, logs, database state, file paths, what's running — SSH into the VM and look it up rather than asking the user. The VM is a live, authoritative source. Check `.env` files, PM2 configs, Apache configs, logs, and file structure. Also check `~/repos/privateContext/` locally for credentials and reference files. See `privateContext/infrastructure.md` for access details.

**Why:** The user treats the VM and local machine as a unified environment. Asking for information that's already discoverable wastes time.

**Don't assume infrastructure.** Never assume Docker, Kubernetes, or any specific container runtime is available. Most services run as bare PM2 processes on the VM. Check `privateContext/infrastructure.md` and `knowledgeBase/infra/vm-overview.md` for the actual service topology before trying container commands.

## Check Infrastructure Before Assuming

When encountering a database connection, service, or dependency that isn't reachable locally, check the actual infrastructure before guessing at local tools:

1. Check `knowledgeBase/infra/` for the service's documented location and architecture
2. Check `privateContext/` for connection details and credentials
3. Try SSH-ing to the VM — most services run on the cloud VM, not locally
4. Only try local tools (Docker, localhost) if the above confirms local deployment

**Why:** A session assumed Docker for a PostgreSQL connection when the DB was on the VM. This system has no Docker installed — the knowledgeBase and privateContext document all services. Wasting time on wrong assumptions is avoidable.

## Apache ProxyPass Trailing-Slash Gotcha

When Apache `ProxyPass` is defined with a trailing slash (e.g., `ProxyPass /app/ http://...`), the bare path `/app` does NOT match. After OIDC auth, the browser returns to the original URL (without slash), causing a 404 as the request falls through to WordPress.

**Fix:** For every `ProxyPass /app/` directive, add a matching redirect:
```apache
RedirectMatch ^/app$ /app/
```

This pattern affected ClaudeNet, Epic Auth, and other services after adding an OIDC-protected project index page (2026-04-28). The `/manchu` route already had this redirect, which is why it worked while others broke.

**When adding a new ProxyPass directive**, always check whether it uses trailing slashes and add the `RedirectMatch` if so.

## VM SSH Access

The GCP VM username is **not** the same as the local username. Before SSH-ing or writing paths that reference the home directory, check `privateContext/sensitive-identifiers.md` for the correct username — hardcoding the wrong one is a recurring source of deploy failures. Always use `$HOME` or `~` in scripts rather than hardcoded paths like `/home/<user>/`.
