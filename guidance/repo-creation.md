<!-- Load when: checklist for new repos: cross-cutting guidance incorporation, CLAUDE.md structure -->
# Repo Creation Checklist

When creating a new repo or writing a new CLAUDE.md, follow this checklist to ensure cross-cutting guidance is incorporated from the start.

## Pre-Write: Cross-Reference agentGuidance

Before writing the CLAUDE.md, scan the following guidance files for rules that apply to this repo's output targets and patterns:

| If the repo... | Read these guidance files |
|---|---|
| Outputs to Google Docs | `guidance/mcp-tools.md` (Google Docs Formatting section) |
| Posts to Discord | `guidance/discord-integration.md` |
| Posts to WordPress | `guidance/wordpress-auto-posting.md`, `guidance/auto-posting.md` |
| Writes in the owner's voice | `guidance/written-voice.md` |
| Has a deploy target | `guidance/deployment.md` |
| Uses auth/OAuth | `guidance/auth-basepath.md` |
| Is a Tampermonkey script | `guidance/tampermonkey.md` |
| Uses browser-agent | `guidance/browser-page-reader.md` |
| Has tests | `guidance/testing.md` |

Incorporate applicable rules directly into the CLAUDE.md rather than assuming the agent will check guidance files at runtime. CLAUDE.md is loaded automatically; guidance files are not.

## CLAUDE.md Structure

Every CLAUDE.md should include:

1. **What this repo does** (one paragraph)
2. **Commands** (build, test, dev)
3. **Output format rules** (if the repo produces formatted output)
4. **Key files and architecture** (if non-obvious)
5. **Constraints** (what NOT to do, security considerations)

## .gitignore Requirements

Every new repo must have a `.gitignore`. At minimum it should exclude:

```
.env*
*.pem
*.key
*.p12
*.pfx
node_modules/
```

Add repo-specific patterns on top (e.g., `*.db`, `*.sqlite`, build outputs, log dirs). A security audit of 30 public repos (2026-06-27) found 3 repos entirely missing `.gitignore` and 4 with incomplete patterns — both preventable at creation time.

## Post-Write: Verify

- [ ] `.gitignore` exists and includes `.env*` + private key patterns (`*.pem`, `*.key`, `*.p12`, `*.pfx`)
- [ ] No raw markdown syntax in output format rules if output targets Google Docs
- [ ] No secrets, credentials, or private infrastructure details
- [ ] Commands section matches `package.json` scripts
- [ ] Output format rules are testable (could you check compliance by reading the output?)
- [ ] Cross-cutting rules from agentGuidance are incorporated, not just referenced

## Adding to Autonomous Scans

After creating the repo:
1. Add it to `~/repos/autonomousDev/config.json` repos list (if it should be scanned by learning-agent and auto-dev)
2. Ensure `context.md` and `progress.md` exist (use templates from `agentGuidance/templates/`)
