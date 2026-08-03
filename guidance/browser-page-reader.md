<!-- browser-page-reader.md | Last updated: 2026-05-10 -->
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

### Tabbed pages hide every tab in static HTML; extract the hidden containers (2026-07-30)
page-reader --text-only and WebFetch return ONLY the active tab of a tabbed page (conference agendas, docs sites, pricing tables). The other tabs are usually already present in the static HTML inside sibling containers with display:none, so nothing needs a headless browser.

Diagnosis: curl the page, then find the tab handler and its container class:
  grep -oE '<div class="[a-z-]*tab[^>]*>[^<]*' page.html

Extraction: track div depth from each container's start offset instead of regex-matching nested HTML. A ~15-line Python scan over the raw file recovers every tab:
  idxs = [m.start() for m in re.finditer(r'<div class="resource-container', h)]
  # walk forward from each idx counting '<div' / '</div' until depth returns to 0

Hit on 2026-07-30 pulling the Agentic AI Summit 2026 agenda from rdi.berkeley.edu: page-reader returned only the 'Plenary - Saturday' tab, but all 7 stage tracks (Plenary/Atlas/Nexus/Compass across both days) were sitting in the downloaded HTML.

Trap: do NOT use a keyword count as an emptiness test. Grepping 'Atlas' returned 4 hits and looked like the track was missing, because tab CONTENT rarely repeats the tab LABEL.

Rule: before concluding a page needs JS execution, download the raw HTML and check for hidden sibling containers.

### A negative result only means something if you first PROVE you reached the state you are testing; on an SPA a URL param is not a state change (2026-08-02)
Before reporting 'source X does not expose Y', you must show evidence that the client actually entered the state where Y would appear. Otherwise you are reporting on your own setup, not on the source.

2026-08-02, Hyatt award rates: loaded /shop/rooms/<id>?rateFilter=WORLD_OF_HYATT_AWARD, saw no point values, and concluded across several rounds that Hyatt withholds award pricing. The URL parameter never activated award mode. The page has a real control -- input[type=checkbox][aria-label='Use Points'] -- and only after clicking it did the cards re-render into 'Points/Night' rows. The eventual conclusion happened to hold, but it was unearned for most of the investigation, and the same mistake could as easily have produced a confident WRONG answer.

The knowledge was already written down. travel-assistant's own notes record that direct navigation to Amex FHR /search-results returns 0 results because server-side session state is never established, and that the SPA form must be driven in the same tab. Same class, previously documented, not applied. So the rule is not 'learn this fact', it is 'run this check'.

THE CHECK, before any 'X is not available / not exposed / blocked' claim:
1. Name the state the data requires (filter on, tab selected, logged in, consent accepted).
2. ASSERT that state from the DOM, not from the URL and not from the action's return value. Read back the control: input.checked, aria-pressed, aria-selected, the active class.
3. Only then interpret an empty result.

State the assertion in the report: 'toggle confirmed checked:true, award rows rendered, values blank' is a finding. 'I passed the filter param and saw nothing' is not.

Corollaries from the same session:
- A URL/query parameter is a REQUEST for state on an SPA, never proof of it. Frameworks routinely ignore params they only emit.
- An action returning success is not proof it acted. cdp-click returned clicked:true on every attempt while the checkbox stayed unchecked, because a --bg tab put the element outside the rendered viewport and document.elementFromPoint() at its own centre returned null. Verify by re-reading the control's state.
- Prefer the element's native activation (input.click() on a checkbox) over synthesized coordinate clicks; it is what actually flipped the control here.
- When several similar controls exist, a generic selector silently hits the first. This page had TWO label.switch>span.slider pairs ('Accessible Room' and 'Use Points'). Scope with :has(), e.g. label.switch:has(input[aria-label='Use Points']) span.slider.
- Placeholder text mimics data. The only points-like string while loading was '1234 Points', a skeleton. Do not accept the first regex hit as a value.

### To automate a site feature, DRIVE the feature in a real browser first and read the URL it produces - do not assemble candidate URLs (2026-08-02)
When you need a site's X-mode page (award/points pricing, a filtered search, a specific rate plan), the FIRST action is to use the feature the way a person does and capture the URL/request the application itself lands on. Only then write the automation.

2026-08-02, hotel chain award rates. I spent many rounds assembling candidate URLs, inventing parameter values, and driving widgets by selector. The owner clicked into Choice's own search-with-points flow and pasted one URL:

  .../rates?checkInDate=&checkOutDate=&ratePlanCode=SRD&view=undefined

ratePlanCode=SRD works on a COLD deep link. It deleted an entire driven flow I had just built and verified (load root -> close a native <dialog> -> navigate in the same tab -> trusted click button.points-toggle -> read from main). That flow worked and returned the same value; it was simply unnecessary, and it was fragile in three ways the one-liner is not: it steals window focus, it depends on a class selector that will rot, and it needs a composited tab.

Costs of getting this order wrong, all incurred in one session:
- Invented an enum value (rateFilter=WORLD_OF_HYATT_AWARD; the real one is woh) and concluded from the empty result that the chain withheld the data. Wrong, and it reached three commits before being overturned.
- Declared Choice 'blocked by a locale interstitial' after mistaking a native <dialog>'s residual DOM text for a block.
- Declared IHG 'blocked' before finding qAAR=IVANI.

Procedure for a new site:
1. Open the site in the real browser. Use the feature by hand: pick the destination, set dates, select the points/award/filter mode.
2. Capture the URL AND the XHR the page fires (network capture) at the moment results appear.
3. Reproduce that URL cold in a fresh tab. If it renders, the adapter is a URL builder - the best possible outcome.
4. Only if a cold deep link genuinely fails do you build a driven flow, and then record WHY (e.g. IHG disabled its deep-link route in April 2026, so its search must be submitted with a trusted click on a foregrounded tab).

SELF-SERVICE ORDER. Asking the owner is the LAST resort, not the first:

1. **Web search the parameter.** This works more often than expected and cost
   nothing: searching for IHG's award URL surfaced a real link carrying
   `qAAR=IVANI` + `qRtP=IVANI`, which was the entire IHG unlock. Search the
   parameter name, the rate code, and `site:<domain>` deep links; award-travel
   blogs and FlyerTalk routinely paste working URLs.
2. **Drive the filter yourself and read `location.search`.** Works where the
   site keeps state in the URL.
3. **Capture the XHR** the control fires, including REQUEST BODIES. Choice is
   the case that needs this: clicking its points toggle changes the rendered
   rates but leaves the URL untouched, and a URL-only network listing of 159
   requests showed no rate-plan parameter. `ratePlanCode=SRD` is not reachable
   by (1) or (2) -- web search did not surface it and the URL never changes.
4. Only then ask.

Do not stop at (1) failing. Each step reaches something the previous one
cannot.

### Search BROADLY, then VERIFY on the page

Two failure modes, both hit in one session:

**Too narrow a query.** Searching the exact string `"ratePlanCode=SRD"` returned
nothing and I concluded the parameter was unfindable. Searching the HUMAN
phrasing -- `rate plan SRD flyertalk` -- surfaced it immediately, in a FlyerTalk
thread titled "Loyalty Points Guarantee is not valid without rate plan SRD".
Vary the framing before concluding a parameter is undocumented:
- the exact `param=value` string
- the human phrasing ("rate plan SRD", "award rate code")
- forum/blog scoped (`flyertalk`, `reddit`, `thepointsguy`, `site:<domain>`)
- the error message a user would post about it

**Trusting a search result without testing it.** Web search gave IHG's
`qRtP=IVANI`, which is real and DOCUMENTED and no longer works -- IHG disabled
the deep-link route in April 2026, so it now only populates the dropdown. Only
loading it in a real browser revealed that. Blog and forum posts are snapshots;
vendors change these silently.

**So the loop is: search broadly -> collect EVERY candidate -> load each in a
real browser -> keep what actually renders.** A parameter is "confirmed" only
after the page shows the data, never because a search result mentioned it.
