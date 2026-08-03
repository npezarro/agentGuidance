# Fact-Checking External Claims

## Why this exists

2026-07-03, #requests CC-recommendation thread: across four turns an agent
asserted (a) "Amex welcome bonus eligibility is per-product variant" (outdated —
family language unified the personal Platinum variants), and (b) "credits are
per-product, not per-card" (fabricated — backwards). Both were stated
confidently from model memory, both were material to a "should I apply for this
card" decision, and both were only corrected after the user pushed back. A
third error came from trusting a stale local file (card-portfolio.md) over the
user's own statement about his own card.

The failure mode is NOT "the model didn't know." It's that the model answered
anyway, and that deciding when to check was left to the model's own judgment
of whether a domain felt "fast-moving."

## The rule

**If a factual claim is (1) external to this ecosystem and (2) actionable by
the user, verify it with a current search before asserting it. No
self-assessment of volatility.**

Covered claim classes (non-exhaustive):
- Credit card / bank / issuer rules: bonus eligibility, family language,
  credit stacking, application rules (5/24 etc.), offer amounts and deadlines
- Prices, fees, promotions, availability of products or services
- API/SaaS pricing, rate limits, model names, deprecations
- Software versions, EOL dates, breaking changes
- Legal/policy/immigration facts, program rules, published schedules

Not covered (verify against internal sources instead): anything about the
user's own accounts, infra, repos, or history — for those, the actual source
(DB, Gmail, git, the user's own statement) is the check, per ESSENTIAL rule 3.

## Procedure: the `fact-check` skill

Before posting a research-type answer (recommendations, comparisons,
eligibility/how-much/what-happens-if questions), run the draft through the
`fact-check` skill (`~/.claude/skills/fact-check`). It:

1. Extracts the discrete external-actionable claims from the draft
2. Runs a current-year web search per claim (parallel)
3. Returns per-claim verdicts: CONFIRMED / OUTDATED / CONTRADICTED / UNVERIFIED
4. Requires the answer to be revised for anything not CONFIRMED, and UNVERIFIED
   claims to be labeled as unverified in the final answer

For a single claim mid-conversation, a direct WebSearch with the current
month/year in the query is an acceptable lightweight equivalent — but the
search must actually happen before the assertion is posted.

## Precedence of sources

1. **The user's own statement about their own accounts/actions** — beats
   everything for existence-type facts; if internal data disagrees, the data
   is stale: say so, verify at the real source, fix the data.
2. **Current primary/web sources** (issuer terms pages, official docs,
   Doctor of Credit / Frequent Miler-class trackers) — required for external
   rules and offers.
3. **Internal curated files** (card-portfolio.md, wiki) — authoritative only
   for what they own (benefits detail, member numbers), never for external
   rules, and never over the user.
4. **Model memory** — never sufficient for a covered claim. It generates the
   hypothesis; the search confirms it.

## Contradicting your own prior research

If an earlier turn in the same conversation established a researched fact and
you are about to assert the opposite, that is a red flag, not a correction.
Re-verify with a search and explicitly reconcile ("earlier I found X; the
search now shows Y because Z") — never silently flip.

## Deliverable URL liveness

Any URL you write into a deliverable that leaves the ecosystem (resume,
portfolio, cover letter, LinkedIn post, anything sent or published) is an
externally-checkable fact. Before writing it, curl the exact URL and confirm
it serves the intended public page (HTTP 200 plus a real page, not a redirect
to login and not a bare API). Gate the write on the check; do not ship a hedge
like "confirm live status" about something you could verify in seconds.

These are NOT liveness signals, and each has burned a real deliverable:
- a repo exists on disk (`ls ~/repos/<app>` says nothing about a public URL);
- a PM2 process is `online` (a running service with only `/api/*` routes
  serves no browsable page);
- a memory or index line says "LIVE" (memories are point-in-time and often
  mean "deployed", not "public page exists" — read the full memory, not just
  the one-line index, and then still curl it).

Origin (2026-07-14): "Synthetic Panel (example.com/panel)" was written into a
resume and portfolio as a public product. `/panel` 404s: it is an
internal-first API (only `/api/*`, requires an `X-Panel-Key` header). The
author relied on a `MEMORY.md` "LIVE example.com/panel" index line and a
repo-exists `ls`, neither of which proves public liveness. Use curl per
`knowledgeBase/patterns/url-liveness-detection.md`.

## A 200 Response is Liveness, Not Freshness (2026-07-23)

A URL returning HTTP 200 with a plausible title proves the page is *live*, not that its content is *current*. Job/listing aggregator sites in particular keep expired postings reachable indefinitely — a 4-year-old listing can 200 with a real title next to genuinely fresh ones. Do not conflate the two checks, and never derive a "posted/updated" date from your own discovery timestamp when the source doesn't supply one — that manufactures false freshness for content of unknown age.

**How to apply:** when a pipeline needs to judge whether a piece of external content is current (job postings, product listings, news items), treat "unknown post date" as a distinct, neutral state rather than defaulting to "new" — surface it as such (e.g. an "age unknown" label) and exclude it from freshness-gated views rather than assuming recency. Prefer a real published-date field from the source (schema.org `datePosted`/`dateModified` JSON-LD, an ATS API field) over inference. Applies to any pipeline that aggregates externally-sourced, potentially-stale content: job boards, deal/coupon feeds, marketplace listings.

## "Known / reputable brand" is a factual claim — verify provenance

Calling a brand "known", "established", "reputable", or "trusted" is an
externally-checkable claim, not flavor. Do not assert it from Amazon star
counts or review volume — that is the exact fake-review signal a skeptic gate
is supposed to catch, laundered into credibility. Before applying any such
label, run one search (`who makes <brand>` / `<brand> company history`) and
classify:
- **Established** — an independent company with verifiable history and
  distribution beyond a single marketplace (e.g. Norpro, founded 1973).
- **Amazon-native / marketplace label** — an invented seller brand (often an
  all-caps or nonsense word) sold mainly on Amazon/Walmart with no independent
  history (e.g. IMEEA is an Amazon-native label; FLAFSTER is a 3-person family
  side-hustle). Never call these "known brands"; they can still be fine budget
  picks, but justify that on specific evidence, not borrowed reputation.

Never contradict your own skeptic gate: flagging "no-name" products as a trap
while presenting same-tier Amazon-native brands as "known brands" in the same
guide is the failure this rule exists to prevent.

Origin (2026-07-28): a shopper skewers guide listed IMEEA and FLAFSTER as
"known brands" next to the genuinely-established Norpro. Fixed in all three
buying-guide instruction sets (buying-assistant/CLAUDE.md, claude-skills
buying-guide/SKILL.md, shopper/docker/CLAUDE.md) with a Brand provenance gate.

### Amex merchant-coding research: DoC table is stale, issuer pages 403, reddit blocked to WebSearch (2026-08-01)
When researching which merchants trigger an Amex category statement credit (wireless/streaming/shipping), three constraints bite:

1. Doctor of Credit's 'Amex Benefits Workshop' sortable table is the best aggregate source, but almost every data point in it is dated 2020. Always extract the date column (page-reader --text-only + grep beats WebFetch, which drops the dates), cite the age, and treat 'Works'/'Does not work' as unproven rather than settled. Example: it lists Tello as Works (2020-07-02) and US Mobile as Does not work (2020-05-13) - both six years old as of Aug 2026.

2. Amex's own benefit terms pages under global.americanexpress.com return HTTP 403 to WebFetch and page-reader. Issuer terms therefore have to come from two independent secondary sources (awardwallet + upgradedpoints worked), and the answer should say so rather than implying the issuer was read directly.

3. reddit.com is blocked to WebSearch (API Error 400: 'domains are not accessible to our user agent'), including via allowed_domains. Crowd-sourced data points need an aggregator (Doctor of Credit, FrequentMiler, Miles to Memories, bestmvno) or page-reader instead.

Practical consequence: recommend a test charge before committing to a carrier whose coding rests only on an old data point, and record the evidence gaps explicitly in the deliverable.
