# Tampermonkey Userscript Standards

## Auto-Update Headers (Required)

Every `.user.js` file must include `@updateURL` and `@downloadURL`. For private repos, point at `example.com` (not GitHub raw URLs — auth fails for private repos).

```js
// @updateURL    https://example.com/<script-name>.user.js
// @downloadURL  https://example.com/<script-name>.user.js
```

- Bump `@version` on every change so Tampermonkey detects the update
- Deploy: `scp` the file to VM `/var/www/html/`, then open the URL in Edge to trigger install
- **Always add new scripts to `example.com/install.html`** — centralized install page for all userscripts
- **Public scripts: prefer GitHub Gist raw URLs** for `@updateURL`/`@downloadURL` instead of VM hosting. Apache prefork workers on the VM can saturate under load from long-polling connections (browser-agent), making VM-hosted TM auto-updates unreliable. Use `https://gist.githubusercontent.com/<user>/<gist-id>/raw/<filename>` for public scripts.

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

## Debug & Verbose Logging

Ship userscripts with all debug/verbose logging flags **disabled**. Use boolean constants (`const DEBUG = false`) and gate console output behind them. Never commit `true` to production — users get console spam they can't silence, and it masks real errors in the browser console.

This bit both ChatGPTCompletionChime and GeminiCompletionChime simultaneously (April 2026): `HEARTBEAT_LOG` and `NET_DEBUG` flags were left enabled, producing console output every 750ms for all users.

## YouTube DOM Resilience

YouTube frequently changes DOM structure, removing elements and attributes without notice. Userscripts targeting YouTube must be defensive:

- **Don't rely on attributes like `[is-active]`** for element detection. YouTube removed this from `ytd-reel-video-renderer` in April 2026 without deprecation.
- **Use visibility checks** (`offsetHeight > 0`, `getComputedStyle`) instead of inline style or attribute presence. Invisible elements (e.g., `#movie_player` on Shorts pages) can return stale references.
- **Target stable container IDs** as primary selectors (`#shorts-player`, `#player-container-id`), with fallbacks to class-based selectors (`.player-container`).
- **Mobile containers change independently.** `ytm-player` and `ytm-shorts-player-renderer` can be removed on mobile while desktop equivalents persist. Always test mobile paths separately.
- **MutationObservers need `subtree: true`** for Shorts page navigation detection. YouTube's SPA transitions swap deep subtrees, not top-level elements.
- **Debounce MutationObservers** (250ms minimum) when observing Shorts containers. Swipe navigation triggers many rapid mutations; without debouncing, observers fire dozens of times per swipe causing UI thrashing and race conditions.
- **Use session-scoped variables for SPA state.** For state that should persist across SPA navigation (e.g., user-set speed surviving Shorts swipes) but reset on page leave, use module-level variables instead of GM_setValue. GM_setValue is for persistent cross-session storage; module-level vars naturally reset when the page unloads.
- **Detect navigation via video src changes, not container observers.** For SPA navigation detection (e.g., Shorts swipes), track `video.src || video.currentSrc` changes in the body-level MutationObserver rather than watching for platform-specific container mutations (`ytd-*` on desktop, `ytm-*` on mobile). This is platform-agnostic and works regardless of DOM structure differences. Compare against a `lastVideoSrc` variable with debouncing (300ms) to avoid redundant re-injection.
- **Bump the major version** when adapting to YouTube DOM changes, as the fix typically affects multiple code paths (desktop, mobile, Shorts, fullscreen)
