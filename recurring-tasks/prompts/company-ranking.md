IMPORTANT: This is a non-interactive session. Do NOT ask for confirmation. Execute the task directly. Make reasonable choices and note them in your output.

Date: {{DATE}}

You are working in a job search repository at {{WORKING_DIR}}. Your task is to re-rank company-specific role listings.

## Task: Re-rank Role Listings

1. **Find company-specific role files** in `{{MATERIALS_DIR}}/`. Look for files with company names that contain role listings (e.g., `google_pm_roles.md`, company-specific catalogues). Read each one.

2. **For each file with 10+ roles**, reorganize from any existing grouping into a single numbered ranked list (Rank 1 through N), ordered by these weighted criteria:

   **AI Development Closeness** (heaviest weight): Roles where the PM directly shapes AI model capabilities, evaluation, or core product features powered by LLMs rank highest. Growth, trust/safety, governance, and support roles rank lower.

   **YoE Match** (high weight): The candidate has {{YOE}} years of PM experience. Roles requiring 10+ years rank highest; 8 years is acceptable; 5-7 years is underleveled; 3-4 years is significantly underleveled.

   **Location** (medium-high weight): SF first, then South Bay (Mountain View, Sunnyvale, San Jose), then other US locations. {{PREFERRED_LOCATION}} is the primary target.

   **Salary** (medium weight): Higher listed base salary ceiling ranks higher among otherwise-equal roles.

3. **Remove these categories** (list them in a "Removed Roles" table with reasons):
   - Non-PM roles (e.g., "Product Support Manager")
   - Early-career/APM/intern roles
   - International-only postings (no US location)
   - Closed/expired listings

4. **For each ranked role, include:**
   - Role title and original reference number
   - Team, location, salary range, requirements
   - A "Why #N" explanation justifying the ranking position
   - Application link

5. **Add at the end:**
   - Summary statistics table (total ranked, removed, count by YoE tier, count by location, count with $200K+ ceiling)
   - "Quick-Apply Top 5" list highlighting the strongest matches

6. Keep each file as a single self-contained markdown document.

## Commit and PR

1. Commit to branch `claude/company-ranking-{{DATE}}`
2. Update `progress.md`
3. Push and open a PR: "Re-rank company role lists ({{DATE}})"
4. PR body should summarize which files were re-ranked and any notable changes (roles removed, new #1 picks)

## Constraints
- No em dashes; use commas, semicolons, or colons instead
- Preserve application links exactly as they appear
- Do not remove roles unless they meet the removal criteria above
