<!-- Load when: research depth and methodology before producing guides or recommendations -->
# Deep Research Before Recommendations

When the user asks you to research a topic and produce a guide, recommendation, analysis, or buying decision, the research phase must be thorough before you start writing. Surface-level research produces surface-level guides, and the user ends up doing the real research themselves. That defeats the purpose.

## When This Applies

Any task where you are producing a deliverable based on external research:
- Setup guides, how-to guides, tutorials
- Product/service comparisons and recommendations
- Buying guides and price optimization
- Technology evaluations and architecture decisions
- Troubleshooting guides for unfamiliar tools
- Any "research X and tell me what to do" request

Does NOT apply to: tasks where you already have deep knowledge, pure code implementation, or tasks using only local/repo context.

## Minimum Research Standard

### 1. Source Diversity (at least 3 of these categories)
- **Official documentation** -- the product's own docs, FAQ, setup guide
- **Community forums** -- Reddit threads, Stack Overflow, GitHub issues, Discord servers
- **Recent blog posts/tutorials** -- published within the last 12 months
- **Video content** -- YouTube walkthroughs (check descriptions and comments for gotchas). **Read the transcript, not a third-party recap** -- see below.
- **Comparison/review sites** -- when evaluating alternatives

A guide built from 2-3 WebSearch results and their top links is not research. That's skimming.

### 1b. YouTube: pull the caption track, don't settle for a recap (2026-07-30)

Third-party blog recaps of a talk are lossy and often wrong about emphasis. If a video matters to the answer, read what was actually said. The `yt-video-review` skill uses Whisper, which is right for videos **Nick owns** (needs word-level timing). For **someone else's** talk, captions are far faster -- 3.8 hours of video took seconds:

```bash
yt-dlp --skip-download --write-auto-subs --write-subs \
       --sub-langs "en.*" --sub-format vtt -o "%(id)s.%(ext)s" "<url>"
```

Two mandatory post-processing steps, or the output is unusable:

1. **Dedupe.** Auto-caption VTT uses rolling display, so each cue repeats prior lines and a naive strip yields ~3x duplicated text. Strip `<c>` karaoke tags, unescape HTML, drop any line matching the last ~6 emitted lines, then reflow into ~45s timestamped paragraphs so chunks are readable and citable.
2. **Correct proper nouns.** Auto-captions mangle names badly and *will* make you misquote. Observed in one session: "Tarik Shaupar"/"Derek" = Thariq Shihipar; "Kat Woo" = Cat Wu; "Simon Wilson" = Simon Willison; "cloud"/"quad"/"claw" = Claude; "grap" = grep. Captions also drop plurals. Correct names in your prose, but **keep quotes exactly as captured** so they stay grep-verifiable, and say so in the deliverable.

**Then count terms.** Term frequency on a transcript is cheap and catches what reading misses. Run `grep -oic` for the 5-10 terms central to your question. In one session, counting `eval` vs `verif` across four talks by the same speaker (39 uses of "verif" and 0 of "eval" in a 112-minute talk) revealed his real conceptual vocabulary and inverted the recommendation. A zero-count is a finding, not an absence of data.

**Verify delegated reads.** When subagents read long transcripts, require verbatim quotes with timestamps, then re-grep their key claims in the main thread before publishing. Cheap insurance, and it makes every claim defensible.

### 2. Gotcha Hunting
Before recommending any setup or product, explicitly search for problems:
- Search "[product] problems [year]", "[product] not working", "[product] issues reddit"
- Read at least one negative/critical thread to understand failure modes
- Include known limitations and common pitfalls in your deliverable
- If something looks too easy, it probably has a catch you haven't found yet

### 3. Cross-Referencing
- Key claims (compatibility, pricing, feature availability) must be verified across 2+ independent sources
- If only one source says something, flag it as unverified or single-source
- When sources conflict, note the conflict and investigate which is current
- Version numbers, URLs, and specific steps should be verified against official sources, not just blog posts

### 4. Version and Platform Disambiguation
- Identify which version, OS, hardware, or configuration the advice applies to
- Explicitly call out when different versions/platforms have different paths (e.g., "Chromecast with Google TV" vs "Chromecast dongle" are completely different setup stories)
- Check whether the product has had recent major changes that invalidate older guides
- Note the date of your sources; a 2024 guide for a product that shipped a major update in 2025 may be wrong

### 5. Completeness Audit
Before writing, list the questions a reader would have:
- What do I need before starting? (prerequisites, accounts, hardware)
- What are the decision points? (which path for my situation)
- What can go wrong? (common errors, troubleshooting)
- What does "done" look like? (verification steps)
- What are the ongoing costs or maintenance needs?

If you can't answer one of these, you haven't researched enough. Go back and find it.

### 6. Recency Verification
- Check that URLs you're recommending are still live
- Verify addon/plugin/extension names and installation methods are current
- Look for deprecation notices, service shutdowns, or major migrations
- Prefer sources from the last 6 months over older ones; if using older sources, verify the information is still accurate

## Research Workflow

1. **Scoping search** (2-3 queries): Understand the landscape, identify key concepts and decision points
2. **Deep dive** (3-5 queries + fetches): Read official docs, community threads, and recent tutorials in full
3. **Gotcha search** (1-2 queries): Explicitly look for problems, limitations, and common mistakes
4. **Verification pass** (1-2 fetches): Cross-check critical claims against primary sources
5. **Completeness check**: Review against the audit questions above; fill gaps with targeted searches
6. **Write the deliverable**: Only now

If you're writing after step 2, you skipped half the process.

## Quality Signals

A well-researched deliverable includes:
- Prerequisites and decision trees ("if you have X, do this; if Y, do that")
- Specific version numbers and dates for time-sensitive information
- Known limitations stated upfront, not buried
- Troubleshooting section with actual common errors (not generic "check your connection")
- Links to primary sources the user can reference for updates

## Anti-Patterns

- Writing a guide from the first 3 search results
- Treating search snippets as verified facts without reading the full page
- Skipping community forums (where real users report real problems)
- Presenting one path when multiple valid paths exist for different situations
- Omitting known limitations to make the recommendation sound cleaner
- Not checking whether a free tool has gone paid or vice versa
- Recommending a specific version without checking if it's still current
- **Giving up on a source at the first empty/blocked fetch.** Login walls, paywalls, and JS SPAs are *climbable*, not terminal: escalate through the page-access waterfall (WebFetch → page-reader → feed/transcript tricks → **authenticated browser-agent** → WebSearch). See the `page-access` skill + `guidance/browser-page-reader.md`. Auth-gated pages (LinkedIn, paid newsletters) are exactly what browser-agent is for.
- **Spawning research sub-agents armed only with WebFetch for auth-gated/SPA sources** — they hit the same wall and silently "resolve" by writing a confident summary from search snippets. Hand sub-agents the waterfall (incl. the browser-agent command), or retrieve via browser-agent in the main thread and pass the text down. Always label anything search-derived as secondhand.

### Verify a job posting's flagship product is still on the market before diligence: the product's own site can contradict the JD (2026-07-31)
A live job posting is marketing copy and can be months stale about the company's own product. Headstart's Staff PM posting (2026-07-31) leads with 'we are the team behind the coding agent Friday', and headstart.nyc still shows a 'Try Friday' CTA badged New, but codewithfriday.com states plainly: 'As of 3/27/26, Friday will no longer be available to external users. We're continuing development as an internal tool.' The flagship product had already retreated from the market four months before the req was live.

How to apply: when researching a company for a role, an investment, or a partnership, fetch the PRODUCT's own domain (and its status/pricing/login page), not just the company marketing site and the ATS posting. Compare the three. A withdrawn product, a dead pricing page, or a login wall where a signup used to be changes what the job actually is. Here it turned an apparent product-PM role into a client-delivery role at a services firm, which is a different fit decision.

Corollary: aggregator mirrors of postings drift from the canonical ATS page. Built In showed $240k for the same req the Ashby page listed at $265k. Treat the ATS page (Ashby/Greenhouse/Lever) as canonical and note the conflict rather than averaging it. Same for scraped company stats: getlatka reported 553 employees / $60.8M revenue for a company whose own Built In profile says 22 employees.

### Price tiers can be non-monotonic: a shorter booking can cost more (2026-08-03)
Rental and subscription pricing is tiered, not linear, and the tier boundary can make a SHORTER booking cost MORE than a longer one. Never assume price rises monotonically with duration, and never quote a duration the user happened to mention without bracketing the tier boundary.

Observed 2026-08-03 on enterprise.com's live booking engine (Covina S. Citrus branch, economy, age 25+):
  27 days -> WEEKLY tier  -> $1,094.79
  28 days -> MONTHLY tier -> $965.81   ($129 CHEAPER than 27 days)
  30 days -> MONTHLY tier -> $966.74   (days 29-30 cost ~$0.47/day)

Enterprise's own long-term page states monthly rates begin at 'more than 28 days'. That published copy is wrong; the empirical trigger is exactly 28. Vendor documentation about its own pricing tiers is a hypothesis, not a fact.

Rule: when researching any duration-tiered price (car rental, subscription, storage, cloud commitment), bracket the boundary by quoting N-1, N, and N+2 rather than quoting only the requested N. Report the cliff explicitly, because 'book one day longer and save $129' is often the single most actionable finding in the whole research pass.


## Company-Specific Deliverables — No Invented Product Claims

When building materials ABOUT a specific product or company (interview memos, prototype decks, product analyses, competitive write-ups), only include product capabilities that are:

1. **Verified via public sources** — official docs, press releases, tech blog posts, shareholder letters, or news articles. Date-stamp and link the source.
2. **Confirmed in the user's own sketch or brief** — if the user described the feature themselves, use their framing exactly.

Do NOT extrapolate, assume, or invent features that "seem like they should exist" or "fit the product vision."

**Why this matters:** Fabricated features read as authoritative claims to a hiring panel, client, or stakeholder. When challenged, the error is harder to recover from than a knowledge gap. Real case: Netflix final-panel prep required a full ground-up rebuild after agents invented watch parties (not a Netflix feature), a 50% TV access target (no such target exists), and kids-profiles-with-games (false) — costing a full session.

**Self-check before submitting any company-specific deliverable:** For each product claim, ask "where is the public source for this?" If you can't point to one, mark it as assumed or cut it. Reference the user's own words as the floor for what's in scope. Source: Netflix panel prep correction (2026-07-01), S199.

### A successful WebFetch is not a faithful read: open the document when the answer is a specific limit (2026-08-05)
WebFetch retrieves a page/PDF and then answers your prompt against it with a small fast model. That summarization step can fail SILENTLY and CONFIDENTLY on a document it read correctly - the retrieval succeeding tells you nothing about the answer being right.

2026-08-05, car rental research: WebFetch on Amex's own Premium Car Rental Protection T&C PDF reported a 31-day coverage cap (the document says 42) and stated 'the document does not contain distinct California-specific pricing' (the document prints two explicit California price tiers). Both errors were material - the correct 42 days and the CA $17.95 price were the session's headline finding. Trusting the summary would have understated coverage by 11 days and lost the best number in the research.

WHAT CAUGHT IT: the same vendor's FAQ, fetched two minutes earlier, said 42 days. **When two fetches of the same vendor's own material disagree, the likely explanation is a bad read, not an inconsistent vendor.** Do not average them or pick the more plausible one.

THE RULE: when the answer you need is a specific number, cap, limit, price, date, or eligibility threshold, and the source is authoritative (a vendor's own terms, policy PDF, spec, or contract), do not stop at the WebFetch summary. WebFetch persists binary content to a local path - Read it directly (the `pages` param handles PDFs). One extra tool call.

Distinct from the existing anti-patterns in this file: those cover WebFetch FAILING on blocked/SPA pages and sub-agents laundering search snippets. This is the harder case - a clean, plausible, wrong answer from a document that was genuinely fetched. There is no error signal to notice.
