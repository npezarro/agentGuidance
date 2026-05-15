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
- **Video content** -- YouTube walkthroughs (check descriptions and comments for gotchas)
- **Comparison/review sites** -- when evaluating alternatives

A guide built from 2-3 WebSearch results and their top links is not research. That's skimming.

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
