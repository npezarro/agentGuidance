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

## Resume Baseline

Use the latest dated resume in `resumes/` as the baseline.

## PDF Conversion

```bash
pandoc file.md -o file.pdf --pdf-engine=pdflatex -V geometry:margin=0.75in -V fontsize=10pt -V linkcolor=blue
```
