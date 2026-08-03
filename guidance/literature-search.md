<!-- Load when: a claim is scientific/medical/technical and primary literature would settle it better than web search -->
# Literature Search (Valency MCP)

Primary-literature search over 44M papers plus a 491M-work citation graph, via the
`valency-mcp` MCP server (user scope, all projects). Use it when the honest answer to
a claim lives in a study rather than on a web page.

## What it actually covers

Measured 2026-08-03 (not from the vendor's docs). Coverage is lopsided, and that
determines whether it is the right tool:

| source | papers | range |
|---|---|---|
| pubmed | 40.4M (91%) | 1965-11 → current |
| arxiv | 4.8M | 2007-01 → current |
| biorxiv | 468k | 2013-11 → current |
| medrxiv | 108k | 2019-06 → current |
| psyarxiv | 58k | 2016-08 → current |
| socarxiv | 24k | 2016-07 → current |
| eartharxiv | 7k | 2017-10 → current |

**Biomedical first, CS/ML second, everything else thin.** Indexed through the current
day, so it is not a stale snapshot. ~34.6M papers carry embeddings, so
`semantic_search_papers` covers most but not all of the corpus — a semantic miss is not
proof of absence; retry with `search_by_title` / `search_by_abstract`.

## When to use it INSTEAD of WebSearch

- A health, nutrition, supplement, or medical claim (`#fact-checking`, reply-to-mom).
  Web search returns the same wellness blogs the claim came from; this returns the study.
- A product-efficacy question in a buying guide ("does this actually work"), as opposed
  to price, availability, or brand provenance.
- An AI/ML/technical claim where the paper is the primary source.
- "Is this finding real / did it replicate" — `get_citing_papers` over the citation graph
  shows whether later work supported or quietly contradicted it. This is the capability
  web search cannot substitute for.

## When NOT to use it

It cannot verify prices, card/issuer eligibility, offer terms and deadlines, software
versions, API limits, or product availability. **There is zero overlap with the
`fact-check` skill's core claim classes** — those still require WebSearch. Reaching for
this on a pricing claim returns nothing and reads as "no evidence found," which is worse
than not asking.

## The peer-review guard (MANDATORY)

bioRxiv, medRxiv, arXiv, psyArxiv, socArxiv and eartharXiv entries are **preprints — not
peer-reviewed**. Citing one as settled science is a quality regression dressed as rigor;
it launders an unreviewed manuscript into authority precisely because it arrived with a
DOI-shaped identifier.

- `journal_ref` present ⇒ it reached a journal. That is the discriminator.
- `journal_ref` absent ⇒ label it **preprint (not peer-reviewed)** inline, every time.
- Only 7.1% of the corpus carries a `license` value, so absent metadata proves nothing
  in either direction. Do not infer quality from missing fields.
- A single study is not a finding. Prefer reviews/meta-analyses, and state sample size
  and whether it was human or animal when the claim is health-facing.

## Tool map (38 tools)

| Need | Tool |
|---|---|
| Concept search | `semantic_search_papers` |
| Exact title/abstract/author/venue | `search_by_title`, `search_by_abstract`, `search_by_author`, `search_by_venue` |
| Did it replicate / who disputed it | `get_citing_papers`, `find_similar_papers` |
| Author credibility, conflicts | `get_author_profile`, `get_author_identity`, `resolve_orcid`, `find_coauthors` |
| Field shape over time | `get_publication_trends`, `get_keyword_trends`, `identify_research_domains` |
| Narrow a result set | `filter_by_date_range`, `filter_by_categories`, `filter_papers_with_doi` |
| Capture sources | `export_papers_bibtex`, `export_papers_csv`, `export_papers_json` |

Plugin skills (`valency@valency-plugin`, user scope) wrap the common paths:
`/valency:profile`, `:network`, `:similar`, `:landscape`, `:trends`, `:reading-list`,
`:fresh-collaborators`.

`get_field_coverage` only supports `journal_ref` and `license`; `category` is an input
filter, not a queryable field, so there is no way to enumerate categories.

## Provenance

`export_papers_bibtex` / `_csv` / `_json` emit citation records directly — route them to
the sourceLibrary repo per `guidance/provenance.md` rather than hand-transcribing. Any
figure taken from a paper is a generated fact and gets marked as such.

## Auth

OAuth, not a token — no key exists or is needed. If it 401s, the fix is re-running `/mcp`
inside Claude Code, **not** hunting for a credential. The OAuth callback port is pinned to
33418 because Valency pre-registers that exact redirect URI; a random port fails the
exchange. On WSL the browser runs on Windows and depends on WSL2 localhost forwarding to
reach the listener in Ubuntu.

MCP tools bind at session start: a server added mid-session shows `Connected` while its
`mcp__valency-mcp__*` tools do not yet exist. Restart before concluding it is broken.
