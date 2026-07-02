<!-- browser-page-reader.md | Last updated: 2026-05-10 -->
# Browser Page Reader (page-reader)

## What It Is
A CLI utility that loads URLs in a headless Chromium browser with full JavaScript rendering and returns structured page content. Built on Playwright, but purpose-built for content extraction rather than browser automation.

## When to Use It
- **JS-heavy pages** that don't render with simple HTTP fetch (modern SPAs, React/Angular sites)
- **Page status checks** where you need to determine if a page is live, changed, or removed
- **Any page where WebFetch or Cheerio returns incomplete/broken content** because the page relies on client-side rendering
- **Getting full visible text** from a page for analysis

## CRITICAL: Use page-reader, NOT WebFetch, for Link Liveness Checks
**WebFetch cannot determine if a JS-rendered page is live or dead.** Many modern sites are SPAs that render via JavaScript. WebFetch returns raw HTML without executing JS, so every page looks "empty" — leading to false negatives. This has caused full-session wasted work.

**For bulk URL checks:** Use `curl + data-attribute parsing` as a fast first pass, then use page-reader for ambiguous results. **Always test your detection method on 1 known-live, 1 known-dead, and 1 fake URL before running a bulk check.**

**Never delegate link-checking to sub-agents using WebFetch** — they'll hit the same SPA rendering wall. Use page-reader or curl in the main thread.

## When NOT to Use It
- Static HTML pages where WebFetch works fine
- Pages you need to interact with (click, fill forms, navigate); use the Playwright MCP for those
- APIs that return JSON directly

## Where It Lives
- **Local (WSL):** `~/repos/page-reader/`
- **VM:** `~/page-reader/`

## Usage

```bash
# Full structured JSON output (title, meta, OG, text, links, signals)
node ~/repos/page-reader/src/index.js <url>

# Just the visible text, no JSON wrapper
node ~/repos/page-reader/src/index.js --text-only <url>

# Longer wait for slow SPAs (default 2000ms)
node ~/repos/page-reader/src/index.js --wait 5000 <url>

# With screenshot (base64 in output)
node ~/repos/page-reader/src/index.js --screenshot <url>

# Compact JSON (no pretty-print, good for piping)
node ~/repos/page-reader/src/index.js --compact <url>

# Custom timeout (default 30000ms)
node ~/repos/page-reader/src/index.js --timeout 60000 <url>

# Authenticated read using a saved Playwright storageState (cookies + localStorage)
# Missing/unreadable file silently falls back to anonymous browsing
node ~/repos/page-reader/src/index.js --storage-state /path/to/session.json <url>
```

## Output Structure (JSON mode)
Key fields in the JSON output:
- `status`: "ok", "error", or "redirect"
- `title`: Page title
- `text`: Full visible text content (the main thing you want)
- `meta`, `ogData`: SEO metadata
- `jsonLd`: Structured data (JobPosting schema, etc.)
- `signals.jobClosed`: Boolean, true if closed-job patterns detected
- `signals.closedReason`: The matched text that triggered closed detection
- `signals.requires`: Array of blockers like "login" or "captcha"
- `timing`: Load and total time in ms

## Signal Detection
Automatically detects:
- **Closed/expired jobs**: "no longer accepting", "position filled", "this job is closed", "job not found", "couldn't find that page", expired JSON-LD dates
- **Login walls**: Password fields + "sign in to continue" patterns
- **Captchas**: reCAPTCHA, hCaptcha iframes
- **Cloudflare challenges**: Detects `cf-mitigated:challenge` header and 403 responses, waits up to 12s for auto-resolution before extracting content. Enables reading pages behind Cloudflare bot protection (e.g., OpenAI careers).
- **Redirects**: When the final URL differs from the requested URL

## Stealth Mode
Use `--stealth` for sites with bot detection:
```bash
node ~/repos/page-reader/src/index.js --stealth --wait 5000 <url>
```
- Randomizes viewport dimensions slightly
- Sets `navigator.webdriver` to false
- Uses `domcontentloaded` instead of `networkidle` (avoids hanging on blocked trackers)
- Sets US locale and timezone

## Calling from Docker Containers

The standard CLI (`node ~/repos/page-reader/src/index.js`) is not accessible inside a Docker container. Use the `page-reader-proxy` PM2 service instead.

**What it is:** An HTTP server (`src/server.js`) running from `~/repos/page-reader`, exposed on port 3092. PM2 process name: `page-reader-proxy`.

**How to call it from a Docker container:**

1. Add `host.docker.internal:host-gateway` to `extra_hosts` in `docker-compose.yml`:
   ```yaml
   extra_hosts:
     - "host.docker.internal:host-gateway"
   ```

2. Call it via HTTP from inside the container:
   ```
   http://host.docker.internal:3092/fetch?url=ENCODED_URL&stealth=true
   ```
   URL-encode the target URL. Use `stealth=true` for bot-protected pages.

**Pattern:** Use as a WebFetch fallback in Docker-bridged Claude CLI system prompts. If `WebFetch` returns a 500, 403, empty body, or bot-block page, retry via the proxy. Only fall back to this after direct WebFetch fails — the proxy uses a full headless browser and is slower.

Source: shopper `docker/CLAUDE.md`, auth resilience session 2026-05-24.

## Browser Automation: Content Script vs External Driver

When automating a site (form submission, navigation, clicking), choose between:

- **browser-agent (content script):** Injected into the live page's JavaScript context. Subject to the site's Content Security Policy. Some sites (payment processors, subscription management pages) block injected scripts or go silent — commands time out with no error.
- **Playwright / puppeteer (external driver):** Owns its own browser process. Not subject to the page's security context. Resistant to CSP blocks.

**Rule:** If browser-agent commands go silent (heartbeat stale, every command times out), the site is blocking content-script injection. Spin up a dedicated Playwright script instead. Do NOT keep retrying browser-agent.

**DOM discovery harness when a scripted flow breaks:** When a site redesigns and selectors stop working, don't guess. Write a throwaway script that walks the new flow and dumps — at each page — visible headings, button labels, link text + hrefs, radio/checkbox labels, and a screenshot. Encode the real selector against actual DOM structure, not guesses.

**Key off structure, not marketing copy:** When detecting page state (e.g., "is the account active?"), prefer durable structural signals (link href patterns, presence/absence of a cancel vs reactivate anchor) over page text strings. Marketing copy changes with every redesign; href patterns change only when the flow changes.

Source: Peloton cancel automation rewrite (2026-06-22) — browser-agent blocked by site; Playwright worked. See `privateContext/recurring-tasks/scripts/peloton-cancel.sh`.

## Browser-Agent Background Tab Command Timeouts

Chrome throttles content-script/page timer polling to ~1 request per minute for tabs that are backgrounded or unfocused. `browser-agent` eval, navigate, click, and type commands targeting a background tab will appear to succeed (the relay accepts the command) but sit unpolled and time out ("Timeout waiting for browser response") — while `/health` and tab listings look healthy.

**Fix (relay v2.7+, 2026-06-30, commit `55d1a74`):** The relay's `translateToExtension()` detects when a target tab's content-script is stale (>10s since last ping) and routes the command to the MV3 extension's CDP path (`cdpEval`/`cdpClick`/`cdpType`) instead. The extension polls via `chrome.alarms` (not throttled by Chrome) and drives any tab via `chrome.debugger`. This routing is automatic and transparent to callers.

**Symptom pattern to recognize:**
- Command targets a tab not currently in the foreground
- `/agent/tabs` shows the tab as alive; `/health` returns OK
- `eval`/`navigate`/`type` all time out with "Timeout waiting for browser response"
- Content-script heartbeat is stale (tab unfocused >10s)

**If you still see background-tab timeouts:** the relay is likely pre-fix. Pull `55d1a74` (`agent-server.js` + `lib/core.js`) and `pm2 restart browser-agent`. No extension update needed.

## Browser-Agent Extension Reload After Updates

When the relay server is updated with changes that involve new content-script messaging (new `ba-*` registration commands, new `resolveTabId` lookup paths), the Chrome extension MUST be reloaded to activate the new content-script features. The relay restart alone is not enough.

**When required:** any update to content-script message handlers or extension-side tab registry logic.

**How to reload:**
1. Open `chrome://extensions` in Chrome
2. Find "Browser Agent" and click the reload icon (↺)
3. Spawn fresh tabs via `browser-cli ensure <url>` after reload so content scripts re-register

**v2.8.0 example (commit `6431607`, 2026-07-01):** The extension gained an `internalId→chromeTabId` registry populated by `ba-register-tab` content-script registration. Without an extension reload, `resolveTabId` fell through to the active-tab fallback, causing CDP commands (screenshot, click, close, focus) to silently target the WRONG tab instead of the named tab.

## Site-Specific Notes
See `privateContext/guidance/` for known limitations and workarounds with specific sites.
