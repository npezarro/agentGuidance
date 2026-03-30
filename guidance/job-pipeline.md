# Job Pipeline & Application Materials

When producing application materials for a role, follow this procedure:

## Steps

1. **Create a prep file** in `assortedLLMTasks/applications/` with:
   - Experience mapping
   - STAR stories
   - Interview questions
   - Cover letter
   - Referral blurb
   - Outreach draft

2. **Create a company folder** (e.g., `applications/adobe/`) with tailored resume and cover letter as both markdown and PDF:
   - `Resume - Company, Role Title.md` / `.pdf`
   - `Cover Letter - Company, Role Title.md` / `.pdf`

3. **Include resume tweak notes** explaining what was changed and why for each role.

4. **Push to GitHub.**

5. **Append the role** to the Job Data tab in the Google Sheet (see `privateContext/infrastructure.md`) with a link in the "Application Materials" column.

## Role Catalogue & Link Quality

When building or updating role catalogues / digest files:

- **Always use direct links to specific job postings.** Never link to generic career pages (e.g., `https://company.com/careers/`). These are useless — the user needs to land directly on the role.
- **Source job IDs from existing catalogue files** in `role-catalogues/` (e.g., `ai_pm_roles_march2026_refresh.md`, `google_pm_roles_march2026_refresh.md`) which contain Greenhouse job IDs, Ashby UUIDs, and deep link URLs.
- **URL patterns by ATS:**
  - Greenhouse: `https://job-boards.greenhouse.io/{company}/jobs/{id}` or `https://boards.greenhouse.io/{company}/jobs/{id}`
  - Ashby: `https://jobs.ashbyhq.com/{company}/{uuid}`
  - Scale AI: `https://scale.com/careers/{id}`
  - Google Careers: `https://www.google.com/about/careers/applications/jobs/results/{id}-{slug}/`
  - OpenAI: `https://openai.com/careers/{slug}/`
- If no specific ID is available, use a **filtered search URL** with the role name as query params (e.g., `?query=agent+harness`) — still better than a bare career page.

### Liveness Verification

Before listing a role as active, verify the link is live:

1. **First pass: curl redirect detection.** Greenhouse closed roles redirect to `?error=true`. Google/Figma redirect to generic career pages. Check with:
   ```bash
   curl -sL -o /dev/null -w "%{url_effective}" --max-time 10 "$url"
   ```
2. **Bot-blocking sites (OpenAI, etc.): use headless Chromium.** Some sites return 403 to curl but work in a real browser. Use playwright via page-reader's node_modules:
   ```bash
   cd ~/repos/page-reader && node -e "
   const { chromium } = require('playwright');
   (async () => {
     const browser = await chromium.launch({ headless: true });
     const ctx = await browser.newContext({ userAgent: 'Mozilla/5.0 ...' });
     const page = await ctx.newPage();
     const resp = await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 20000 });
     console.log(resp.status(), await page.title());
     await browser.close();
   })();
   "
   ```
   A 404 or title mismatch = dead. A 200 with the role title in `<title>` = live.
3. **Never trust HTTP 200 alone.** Google Careers returns 200 for closed roles (JS SPA). Always check the rendered content or redirect target.

## Resume Baseline

Use the latest dated resume in `resumes/` as the baseline.

## PDF Conversion

```bash
pandoc file.md -o file.pdf --pdf-engine=pdflatex -V geometry:margin=0.75in -V fontsize=10pt -V linkcolor=blue
```
