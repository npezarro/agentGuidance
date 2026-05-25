# Doc-Sync Agent — Experience Log

---
## 2026-05-20 | Shopper Conversation Navigation Feature Audit
**Task:** Detect and document CLAUDE.md drift from 6 recent commits
**What worked:** Systematic diff review (git diff HEAD~6..HEAD) + git show for commit context. Started with commit log, then stat summary, then detailed diffs for key files (auth.ts, api/jobs/route.ts, bridge-server.js, JobDetail.tsx). Avoided rabbit holes: Dependabot config and bug fixes skipped as trivial.
**What didn't:** Initially scanned brief commit messages; had to examine actual code changes to understand scope (e.g., commit message "Add conversation navigation" needed JobDetail.tsx diff to confirm outline nav + anchor IDs).
**Learned:** Commit messages alone are insufficient for drift detection. Always inspect changed files. For multi-file commits, focus on: (1) new exports/routes, (2) new UI elements, (3) changed behavior, (4) new env vars/config. Docker changes (entrypoint.sh, user switch, path changes) are significant and need docs — they affect local dev and deployment.

---
## 2026-04-16 | Initial Profile Creation
**Task:** Established doc-sync agent profile to close the documentation lag gap
**What worked:** Scoped to CLAUDE.md only (not guidance files) to keep the role focused
**What didn't:** N/A — initial setup
**Learned:** Documentation lag was flagged as structural in the instruction adherence audit. The learning agent catches it 2-5 runs late. A dedicated doc-sync role that runs immediately post-merge can close the gap to near-zero.
