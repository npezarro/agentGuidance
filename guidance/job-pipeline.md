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

- **Always use direct links to specific job postings.** Never link to generic career pages (e.g., `https://company.com/careers/`) or query-only search URLs (e.g., `?query=agent+harness`). Every link must resolve to a single specific role.
- **Source job IDs from existing catalogue files** in `role-catalogues/` (e.g., `ai_pm_roles_march2026_refresh.md`, `google_pm_roles_march2026_refresh.md`) which contain Greenhouse job IDs, Ashby UUIDs, and deep link URLs.
- **URL patterns by ATS:**
  - Greenhouse: `https://job-boards.greenhouse.io/{company}/jobs/{id}` or `https://boards.greenhouse.io/{company}/jobs/{id}`
  - Ashby: `https://jobs.ashbyhq.com/{company}/{uuid}`
  - Scale AI: `https://scale.com/careers/{id}`
  - Google Careers: `https://www.google.com/about/careers/applications/jobs/results/{id}-{slug}/`
  - OpenAI: `https://openai.com/careers/{slug}/`
  - Roblox (Greenhouse): `https://careers.roblox.com/jobs/{id}?gh_jid={id}`
- **If no ID exists in the catalogues, scrape the job board directly** using page-reader's `--stealth` mode to extract the UUID/ID from the listing page. See "Scraping Direct Links" below.

### Scraping Direct Links from Job Boards

When catalogue files don't have the specific ID for a role, scrape it from the company's job board:

```bash
# Extract all PM role links with UUIDs from an Ashby board
cd ~/repos/page-reader && node src/index.js --stealth --compact "https://jobs.ashbyhq.com/{company}" | \
  node -e "const j=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
  j.links.filter(l => /product manager/i.test(l.text)).forEach(l => \
  console.log(l.text.replace(/\n/g,' ').replace(/\s+/g,' ').trim(), '|', l.href));"

# Query Greenhouse API directly (faster than scraping)
curl -s "https://boards-api.greenhouse.io/v1/boards/{company}/jobs" | \
  node -e "const j=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
  j.jobs.filter(job => /search term/i.test(job.title)).forEach(job => \
  console.log(job.title, '|', job.absolute_url, '| ID:', job.id));"
```

### Liveness Verification

Before listing a role as active, verify the link is live:

1. **First pass: curl redirect detection.** Greenhouse closed roles redirect to `?error=true`. Google/Figma redirect to generic career pages. Check with:
   ```bash
   curl -sL -o /dev/null -w "%{url_effective}" --max-time 10 "$url"
   ```
2. **Bot-blocking sites (OpenAI, etc.): use page-reader `--stealth`.** Some sites return 403 to curl but work in a real browser:
   ```bash
   cd ~/repos/page-reader && node src/index.js --stealth --compact "$url" | \
     node -e "const j=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
     console.log('status:', j.httpStatus, 'title:', j.title);"
   ```
   A 404 or title mismatch = dead. A 200 with the role title in `<title>` = live.
3. **Greenhouse API for bulk checks** (Roblox, Discord, etc.):
   ```bash
   curl -s "https://boards-api.greenhouse.io/v1/boards/{company}/jobs" | \
     node -e "const j=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
     console.log(j.jobs.filter(job => /search/i.test(job.title)).map(j => j.title));"
   ```
4. **Never trust HTTP 200 alone.** Google Careers returns 200 for closed roles (JS SPA). Always check the rendered content or redirect target.

## Resume Baseline

Use the latest dated resume in `resumes/` as the baseline.

## PDF Conversion

```bash
pandoc file.md -o file.pdf --pdf-engine=pdflatex -V geometry:margin=0.75in -V fontsize=10pt -V linkcolor=blue
```
