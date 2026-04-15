# Wiki Consultation

The KnowledgeBase wiki (`~/repos/knowledgeBase/`) contains synthesized cross-repo knowledge. It sits above guidance files and memory, connecting patterns across repos.

## When to Consult the Wiki

Your SessionStart output includes a "KNOWLEDGEBASE WIKI" section listing all available pages. Read a wiki page when:

1. **Working across repos.** Wiki pages map which repos implement a pattern and how they interact (e.g., browser-agent consumers, Discord ecosystem, free games pipeline).
2. **Deploying or changing infrastructure.** Read `infra/vm-deployment-playbook.md` and `infra/vm-overview.md` for constraints, ports, and PM2 services.
3. **Working with an integration.** Discord, browser-agent, OAuth, Tampermonkey, and WordPress all have integration pages documenting cross-repo gotchas.
4. **Debugging a cross-repo issue.** If the bug spans repos, the wiki likely has a page mapping the interaction points.
5. **Modifying instruction architecture.** Read `agent-system/instruction-architecture.md` before changing agent.md, memory, guidance files, or the wiki itself.

## How to Consult

1. Scan the wiki index in SessionStart output for relevant page titles.
2. Read the page directly: `cat ~/repos/knowledgeBase/<category>/<page>.md`
3. Find pages relevant to a specific repo: `bash ~/repos/knowledgeBase/scripts/fetch-context.sh --repo <repo-name>`
4. Search by topic: `bash ~/repos/knowledgeBase/scripts/fetch-context.sh --topic <keyword>`

## What Wiki Pages Provide That Other Sources Don't

| Source | What It Covers | Wiki Adds |
|---|---|---|
| Repo CLAUDE.md | Rules for working in that repo | Which other repos interact with it and how |
| Guidance files | Universal behavioral rules | Synthesized patterns from multiple guidance + privateContext sources |
| Memory | Personal cross-session recall | Structured, schema-validated, cross-referenced knowledge |
| privateContext | Credentials and infra details | Sanitized architecture overviews safe for public repos |

## Do NOT

- Inject full wiki pages into context unless the task directly requires cross-repo understanding.
- Treat wiki as canonical for procedures (that's guidance/) or credentials (that's privateContext/).
- Skip wiki for cross-repo work just because the repo's CLAUDE.md has some context.
- Duplicate wiki content into other files; link to the page instead.
