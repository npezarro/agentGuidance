<!-- Load when: producing any deliverable that contains researched/generated facts; capturing sources -->
# Provenance & Source Capture

Goal: when Nick reviews content later, he can tell **what he wrote** from **what Claude
generated**, and every external fact traces back to a captured, re-findable source.

**Invocable as the `provenance` skill** (claude-skills) — the step-by-step procedure
with quality gates that applies this convention to a deliverable. Producer skills
(write-as-nick, application-packet, resume-variant, buying-guide, deep-research) call
it as their final provenance pass.

Two facets, always applied together:
1. **Provenance marking** — generated facts are attributable to Claude, not Nick.
2. **Source capture** — every external source is recorded once in the private
   `sourceLibrary` repo and linked by a stable ID.

---

## When this applies (scope)

Applies to **deliverables that contain researched or generated facts**: research
reports, buying guides, bios, resumes, cover letters, data tables, figures, company
briefs, competitive analyses, any doc where Claude injects facts it looked up or
inferred.

Does **not** apply to: casual conversation, pure-code output, or opinion/preference
text with no external factual claims.

A "generated fact" = any discrete, checkable claim Claude introduced (not Nick):
figures, dates, names, statistics, quotes, historical/biographical claims, prices,
specs. Nick's own input is never marked — the contrast is the signal.

---

## Two document classes

The marking style depends on whether the artifact is for Nick's eyes or is sent
externally to a human.

### A) Internal review docs (Claude → Nick)
Research reports, buying guides, data tables, company briefs — things Nick reads and
reviews, not forwards verbatim.

- **Inline fact tags** on each generated hard fact, keyed to a source:
  `Revenue hit $4.2M in 2023 [AI·s-4e8bf9d5].` Use `[AI·<id>]` where `<id>` is the
  `source-registry.sh` ID. If a fact is generated but unsourced (inference, estimate),
  tag it `[AI·unsourced]`.
- **Provenance & Sources appendix** at the doc's end:

  ```markdown
  ## Provenance & Sources
  | Fact | Status | Source |
  |------|--------|--------|
  | Revenue $4.2M (2023) | verified | [s-4e8bf9d5] stripe.com/about |
  | Series B (2024) | unverified | [s-1a2b3c4d] techcrunch.com/... |
  ```
  `Status`: `verified` (passed fact-check / primary source) or `unverified`
  (single/weak source, not cross-checked).

### B) External deliverables (Claude → Nick → a human)
Cover letters, resumes, published bios, outreach emails — anything Nick sends or
publishes. **The prose Nick sends must be clean: NO inline `[AI·…]` markers, no
appendix.** Instead:

- **Signal AI-authorship in the title/filename**, not the body:
  `Cover Letter — Stripe [AI-generated].md`, or the Google Doc title
  `Cover Letter — Stripe (AI-generated)`. This is how future-Nick spots that he
  didn't write it, without the recipient ever seeing a marker.
- **Provenance rides in frontmatter + a sidecar**, never in the sent text:
  ```markdown
  ---
  provenance: ai-generated
  author_split: ai   # ai | nick | mixed
  facts:
    - claim: "Series B momentum"
      status: verified
      source: s-4e8bf9d5
  ---
  ```
  When published to a Google Doc, keep the markdown source (with frontmatter) in the
  repo as the provenance record; the Doc itself carries only the `(AI-generated)`
  title.
- Every external factual claim must already have passed the `fact-check` skill
  (ESSENTIAL rule 3). Provenance records the result; it does not replace the check.

### Frontmatter flag (both classes, when the artifact is a file)
Add `provenance: ai-generated` (or `ai-assisted` if Nick co-wrote) to any markdown
deliverable's frontmatter, so a future scan (`grep -rl "provenance: ai"`) finds every
AI-touched doc instantly.

---

## Source capture → the `sourceLibrary` repo

Central, **private** store: `~/repos/sourceLibrary` (registry + cached materials).
Never scatter cached sources into project repos; capture once, cite by ID everywhere.

Driver: `~/repos/agentGuidance/scripts/source-registry.sh` (not on PATH — call by full
path, or `alias sr=~/repos/agentGuidance/scripts/source-registry.sh` for a session).

```bash
sr=~/repos/agentGuidance/scripts/source-registry.sh
# After fetching a page (WebFetch / page-reader), capture it. Idempotent by URL.
# Save the fetched text to a temp file first, pass it as --content-file so the
# material is cached and survives link rot.
id=$("$sr" add \
      --url "https://stripe.com/about" \
      --title "About Stripe" \
      --topic stripe \
      --snippet "the specific line you actually used" \
      --content-file /tmp/fetched.md)
# → prints s-4e8bf9d5 ; use [AI·$id] inline or source: $id in frontmatter

"$sr" find stripe          # re-find everything cited about a topic
"$sr" get s-4e8bf9d5       # resolve one citation
"$sr" list --topic stripe
```

Rules:
- **Capture the material, not just the URL** — pass `--content-file` so the cached
  copy exists. A dead link with no cached copy is a lost citation.
- **Snippet = what you used**, not the whole page.
- The registry dedupes by normalized URL, so re-citing the same source across three
  docs yields one entry and one ID.
- `sourceLibrary` is **private** — cached pages may hold paywalled/gated/bio content.
  Never store secrets even if a fetched page contained them.

---

## Quick checklist (before delivering a fact-bearing doc)

1. Is it internal or external? → pick class A (inline + appendix) or B (clean body +
   title signal + frontmatter/sidecar).
2. Every generated hard fact marked (A) or logged in frontmatter (B)?
3. Every external source captured via `source-registry.sh` with a cached copy?
4. External claims passed `fact-check`? Status recorded (`verified`/`unverified`).
5. File frontmatter carries `provenance:` and (external) title carries `(AI-generated)`.
