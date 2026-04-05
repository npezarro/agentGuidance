# Tampermonkey Userscript Standards

## Auto-Update Headers (Required)

Every `.user.js` file must include `@updateURL` and `@downloadURL`. For private repos, point at `example.com` (not GitHub raw URLs — auth fails for private repos).

```js
// @updateURL    https://example.com/<script-name>.user.js
// @downloadURL  https://example.com/<script-name>.user.js
```

- Bump `@version` on every change so Tampermonkey detects the update
- Deploy: `scp` the file to VM `/var/www/html/`, then open the URL in Edge to trigger install

## Repository

Userscripts may live in their project repo (e.g. `freeGames/src/local-checkout/`) or `~/repos/scripts/`.

## CAPTCHA Bypass Pattern

Tampermonkey scripts running in the user's real browser bypass CAPTCHA (hCaptcha, Cloudflare Turnstile, Arkose FunCAPTCHA) because the browser has legitimate fingerprints and session cookies. This is the preferred approach for automating checkout/claim flows on sites with CAPTCHA.

**Do NOT use:**
- Playwright/Puppeteer headless browsers (always detected)
- CDP remote debugging + Playwright connect (hCaptcha still detects)
- Eval-based loaders (GM_* functions are sandboxed per-script, can't be shared via `window.*` or passed to `eval`)

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
