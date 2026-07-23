<!-- browser-page-reader.md | Last updated: 2026-06-01 -->
<!-- Load when: page-reader CLI for JS-heavy pages -->
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

### SSRF Guard (`src/host-guard.js`)

All proxy requests pass through `isInternalHost()` before fetching. Critical ranges to know:

**172.x gotcha (historical bug, fixed 2026-05-31):** The old guard blocked all `172.*` addresses. Only `172.16.0.0/12` (172.16–172.31.x.x) is RFC1918 private. Public addresses like `172.217.x.x` (Google) are legitimate external hosts and must NOT be blocked. If page-reader ever fails to fetch a public `172.x` URL, check `host-guard.js` first.

**Cloud metadata range (`169.254.0.0/16`):** Always blocked. `169.254.169.254` is the AWS/GCP instance metadata endpoint — a missing block here is a cloud SSRF vulnerability. If the proxy is cloud-hosted (VM, container), verify this range is in the guard.

**DNS rebinding is NOT protected:** `isInternalHost()` inspects hostname strings only, not resolved IPs. A public hostname resolving to a private IP bypasses the check. Documented in the module header — not a bug, a known limitation.

Test coverage: `test/host-guard.test.js` (55 tests covering RFC1918, 172.x ranges, 169.254, IPv6, suffix attacks). Run `npm test` in `~/repos/page-reader` after any guard change.

## The Page-Access Waterfall (escalate; don't surrender at the first empty fetch)
page-reader is **rung 2** of a fixed fallback ladder. The full procedure (with commands) lives in the **`page-access` skill** — invoke it whenever a fetch returns empty, login-walled, paywalled, or JS junk:

1. **WebFetch** — static pages, fast.
2. **page-reader** (`node ~/repos/page-reader/src/index.js --text-only <url>`) — JS SPAs. A 500/empty here is an escalation trigger, not "page is dead."
3. **Feed / alt-endpoint tricks** — clean, no-JS, no-auth; try BEFORE the browser when the host is known:
   - Medium → `medium.com/feed/@USERNAME` (full bodies); Substack → `SUB.substack.com/feed`; blogs → `/feed` `/rss`.
   - YouTube/podcast transcripts → `yt-dlp --skip-download --write-auto-sub --sub-lang en --sub-format vtt`, then clean the VTT.
   - Reddit → append `.json`; GitHub → `raw.githubusercontent.com`.
4. **browser-agent** (`~/repos/browser-agent/browser-cli.sh open|tabs|text`) — drives the **logged-in Chrome**, so it beats **auth walls AND paywalls** (LinkedIn, paid newsletters, gated dashboards). This is the rung WebFetch-only sub-agents are missing.
5. **WebSearch** — secondhand, LAST resort, always flagged as search-derived. Never launder a search summary into a deliverable as if you read the source.

**Sub-agent rule:** never delegate auth-gated or SPA retrieval to a sub-agent armed only with WebFetch — hand it the waterfall (and the browser-agent command) or retrieve via browser-agent in the main thread and pass the text down. An auth/paywall wall is *climbable*, not terminal.

## Site-Specific Notes
See `privateContext/guidance/` for known limitations and workarounds with specific sites.
