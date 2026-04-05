# DevOps Experience Log

---
## 2026-04-04 | pezantTools zero-downtime deploy
**Task:** Deploy a new version of pezantTools to the GCP VM without dropping active file uploads.
**What worked:** Checked `pm2 list` and `ss -tlnp` before touching anything. Built the new version locally, scp'd the build artifacts, then used `pm2 reload` (not restart) for zero-downtime process replacement. Verified the service was live with a curl health check after reload. Confirmed disk usage stayed under 80% with `df -h`.
**What didn't:** Initially tried `pm2 restart` which drops all in-flight connections. Switched to `pm2 reload` which does a graceful rolling restart. The difference matters when users have active uploads.
**Learned:** Always use `pm2 reload` instead of `pm2 restart` for production services with active connections. Restart kills the process immediately; reload starts a new instance and drains the old one. Check `pm2 list` for the "mode" column: only "cluster" mode supports reload. Fork mode falls back to restart behavior.

---
## 2026-03-29 | groceryGenius OOM during build
**Task:** Diagnose why `npm run build` kept getting killed on the GCP VM (4GB RAM) for groceryGenius.
**What worked:** Checked `dmesg | tail` and found OOM killer entries. The Next.js build was consuming 3.5GB+ RAM. Added `NODE_OPTIONS=--max-old-space-size=3072` to the build command and killed the PM2 dev process before building (freeing ~800MB). Build succeeded with no other processes competing for memory.
**What didn't:** Initially tried adding swap space, which made the build complete but took 25 minutes (vs 3 minutes normally). The disk I/O from swapping made the build unusably slow. Freeing memory by stopping non-essential processes was the right fix.
**Learned:** On memory-constrained servers (4GB), Next.js builds and running PM2 processes cannot coexist. Stop non-essential PM2 processes before building. Adding swap is a band-aid that trades OOM for extreme slowness. Always check `pm2 list` and kill dev/staging processes before production builds.

---
## 2026-03-23 | centralDiscord PM2 ecosystem config
**Task:** Set up PM2 ecosystem config for the Discord bot with proper log rotation, restart policies, and environment variable management.
**What worked:** Ecosystem file with `max_restarts: 10` and `restart_delay: 5000` prevented restart storms. Log rotation via `pm2-logrotate` module with 10MB max size and 7-day retention kept disk usage predictable. Environment variables loaded from `.env` via `env_production` block in ecosystem config, not shell sourcing.
**What didn't:** Initially set `autorestart: true` with no max_restarts limit. When the bot hit a persistent error (expired token), it restarted 400+ times in an hour, filling the disk with crash logs. Added the restart cap and delay after that incident.
**Learned:** Always set `max_restarts` and `restart_delay` in PM2 configs. Unlimited auto-restart with a persistent error creates a restart storm that fills disk and generates noise in monitoring. The restart delay should be long enough to avoid hammering external services (5-10 seconds minimum).

---
## 2026-03-20 | runeval nginx reverse proxy
**Task:** Configure nginx reverse proxy for runeval's Next.js app with proper WebSocket support and SSL termination.
**What worked:** Standard reverse proxy config with `proxy_set_header Upgrade` and `proxy_set_header Connection "upgrade"` for WebSocket passthrough. SSL via Let's Encrypt certbot with auto-renewal cron. Checked the existing Apache configs first to avoid port conflicts (Apache was listening on 80 for other sites).
**What didn't:** Forgot to add `proxy_set_header Host $host` initially, which caused Next.js to generate wrong absolute URLs in server-side redirects. The redirects pointed to `localhost:3000` instead of the public domain. Always include all four proxy headers.
**Learned:** The minimum nginx reverse proxy headers for Next.js are: Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto, plus Upgrade/Connection for WebSockets. Missing any of these causes subtle bugs: wrong redirects (missing Host), incorrect rate limiting (missing X-Real-IP), broken auth callbacks (missing X-Forwarded-Proto for HTTPS detection).
