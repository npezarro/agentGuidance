# Tampermonkey Userscript Standards

## Auto-Update Headers (Required)

Every `.user.js` file must include `@updateURL` and `@downloadURL`. For private repos, point at `pezant.ca` (not GitHub raw URLs — auth fails for private repos).

```js
// @updateURL    https://pezant.ca/<script-name>.user.js
// @downloadURL  https://pezant.ca/<script-name>.user.js
```

- Bump `@version` on every change so Tampermonkey detects the update
- Deploy: `scp` the file to VM `/var/www/html/`, then open the URL in Edge to trigger install
- **Always add new scripts to `pezant.ca/install.html`** — centralized install page for all userscripts

## Repository

Userscripts may live in their project repo (e.g. `freeGames/src/local-checkout/`) or `~/repos/scripts/`.

## CAPTCHA Bypass Pattern

Tampermonkey scripts running in the user's real browser bypass CAPTCHA (hCaptcha, Cloudflare Turnstile, Arkose FunCAPTCHA) because the browser has legitimate fingerprints and session cookies. This is the preferred approach for automating checkout/claim flows on sites with CAPTCHA.

**Do NOT use:**
- Playwright/Puppeteer headless browsers (always detected)
- CDP remote debugging + Playwright connect (hCaptcha still detects)
- Eval-based loaders (GM_* functions are sandboxed per-script, can't be shared via `window.*` or passed to `eval`)

## Generic Browser Agent

A general-purpose browser agent (`browser-agent.user.js`) is available for any task that needs live browser interaction — testing web apps, debugging UI, form automation, etc. It matches `*://*/*` and provides 30+ commands via `browser-cli`.

See `privateContext/infrastructure.md` § "Browser Agent" for the full command reference, API key, and architecture. The CLI is at `~/bin/browser-cli`.

## Deployment Pattern for Auto-Checkout Scripts

```
VM discovers task → VM queues job at API endpoint
→ Tampermonkey script polls endpoint from matched domain tab
→ Navigates to target page, automates clicks
→ Acks job completion back to API
```

Key requirements:
- A tab must be open on a `@match` domain for the script to run
- Use `GM_setValue`/`GM_getValue` for cross-navigation state persistence
- Add remote logging (`GM_xmlhttpRequest` POST to server) for debugging
- Include staleness timeout to clear stuck jobs (5 min recommended)

## Remote Agent Pattern (Preferred for Multi-Platform Flows)

For automation spanning multiple sites (game claims, checkout flows), use the **install-once remote agent** pattern instead of per-platform TM scripts:

1. **Thin TM script** — Polls server for commands (click, navigate, read, eval). Installed once, never updated. Matches all target domains.
2. **Server-side orchestrator** — All flow logic lives server-side. Sends sequential commands, handles retries, manages state.

**Why this beats per-platform scripts:** Flow changes (selectors, timing, new platforms) require only server-side updates, not TM reinstalls. The TM script is a generic command executor.

Platform-specific gotchas (discovered via freeGames):
- **Epic:** Checkout iframe requires `eval` to access nested iframe for "Place Order" button
- **GOG redemption:** reCAPTCHA timing is unpredictable; use retry loops with 3-5s waits on Continue/Redeem buttons
- **IndieGala:** "ADD TO LIBRARY" button lazy-loads inconsistently; use `wait-for` with generous timeouts
- **GamerPower API:** Good discovery source for free game listings across platforms
