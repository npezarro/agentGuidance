---
description: Apply when working on deployment, PM2, or production infrastructure
globs:
  - "**/deployQueue.*"
  - "**/ecosystem.config.*"
  - "**/pm2.*"
  - "**/Dockerfile*"
  - "**/.github/workflows/**"
  - "**/deploy*"
  - "**/production*"
---

# Deploy Safety Rules

- Always check VM disk space before deploying (warn if >85%)
- Never clone largeFileStorage repo on the VM - it's 7.6G+ and will fill the disk
- Production branches are called `production`, not `main`
- Staging deploys go through deployQueue.js, production deploys go through index.js reaction handler
- After deploy, verify the PM2 process is online
- The VM has 60GB disk and 4GB RAM - Next.js builds can OOM, run one at a time
