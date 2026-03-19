IMPORTANT: This is a non-interactive session. Do NOT ask for confirmation. Execute the task directly. Make reasonable choices and note them in your output.

You are working in a job search repository. The file `{{CATALOGUE_FILE}}` contains a curated catalogue of AI-focused Product Manager roles. Your target profile: {{TARGET_PROFILE}}.

Date: {{DATE}}

## Task: Expand the AI PM Role Catalogue

1. **Read the existing catalogue** to understand the current format, tier structure, and which companies/roles are already listed. Note the current total count.

2. **Search for new AI/ML Product Manager roles** posted in the last 7 days. Focus on:
   - Tier 1 companies already in the file (Anthropic, OpenAI, Google DeepMind, Meta, Apple, Microsoft, etc.): check for newly posted roles
   - High-growth AI startups (Series B+ or well-funded) not yet in the catalogue
   - Remote-friendly or Bay Area roles at Staff/Senior PM level

3. **For each new role found, add an entry** matching the existing format exactly:
   - Role title, Job ID (if available), location, salary (if listed)
   - "Why apply" blurb tailored to the candidate's profile (LinkedIn Games 0-to-7.5M WAU, Content SEO/GenAI 5x growth, Claude Code power user, 2 AI patents, eval frameworks, fraud/safety systems)
   - Direct application link
   - Place it in the correct tier and company section

4. **Update existing listings** if any roles have been filled/removed or if details have changed (title, salary, job ID). Do not remove existing roles unless confirmed delisted.

5. **Update the summary line** at the top of the file with the new total count.

6. **Update `context.md`** with what changed and any new high-priority additions.

7. **Update `progress.md`** with an entry for this commit.

8. **Commit and push** to branch `claude/job-search-{{DATE}}`. Commit message should summarize the delta (e.g., "Expand AI PM catalogue from X to Y roles across Z companies").

9. **Open a PR** to main using `gh pr create`. Title: "Job search: expand catalogue ({{DATE}})". Body should list notable additions.

## Constraints
- Maintain the tiered structure (Tier 1: highest priority, Tier 2: strong fit, etc.)
- Match the existing markdown format exactly (headings, bullet style, link format)
- No secrets or credentials in any committed file
- No em dashes; use commas, semicolons, or colons instead
