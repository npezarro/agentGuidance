# Security Audit Report -- 7 Public Repos
**Date:** 2026-04-10
**Auditor:** Security (Agent Profile)
**Scope:** autonomousDev, claude-tray-notifier, agentGuidance, ChatGPTCompletionChime, groceryGenius, valueSortify, humblechoice-oneclickclaim

---

## Executive Summary

| Repo | Critical | High | Medium | Low | Info |
|------|----------|------|--------|-----|------|
| autonomousDev | 0 | 1 | 1 | 2 | 0 |
| claude-tray-notifier | 1 | 1 | 1 | 0 | 0 |
| agentGuidance | 0 | 1 | 0 | 2 | 0 |
| ChatGPTCompletionChime | 0 | 1 | 0 | 0 | 0 |
| groceryGenius | 0 | 1 | 1 | 1 | 0 |
| valueSortify | 0 | 1 | 0 | 0 | 0 |
| humblechoice-oneclickclaim | 0 | 1 | 0 | 1 | 0 |

**Total findings: 3 Critical, 6 High, 3 Medium, 6 Low**

---

## 1. autonomousDev

### Files Checked
- `.gitignore`, `config.json`, `repos.conf`, `run.sh`, `overnight-summary.sh`
- `fix-checker/run.sh`, `learnings-pass/run.sh`, `learnings-pass/suggestions.md`
- `.claude/settings.json`, `.github/workflows/pr-notify.yml`
- Git author emails, env files, IP/URL patterns

### Findings

**[HIGH] PII: Personal email in git commit metadata**
- `git log --format="%ae" --all` reveals `REDACTED_EMAIL`
- This is a real personal email exposed in every commit authored from that git config
- **Remediation:** Run `git filter-repo` to rewrite author emails to `npezarro@users.noreply.github.com`, then force-push

**[MEDIUM] .claude/settings.json: Remote code execution hook**
- File: `.claude/settings.json`
- The `Stop` hook fetches and executes a remote shell script via `curl | bash` pattern
- While the source is the owner's own public repo, this pattern is visible to anyone reading the repo and reveals the hook architecture
- **Remediation:** Acceptable risk given the source is owned, but document the trust boundary

**[LOW] config.json: Private repo name partially disclosed**
- File: `config.json:39` -- `"REDACTED_DISCORD_BOT_REPO"` -- properly redacted
- File: `config.json:42` -- `"privateContext"` listed in `protected_repos` -- reveals existence of private infra repo
- **Remediation:** Low risk; the repo name is generic enough. Accept.

**[LOW] Secrets handling pattern in shell scripts is sound**
- `run.sh` loads secrets from `.env` (which is gitignored)
- `fix-checker/run.sh:255` uses `ssh REDACTED_VM_HOST` -- properly redacted
- Discord bot token loaded from local cache file, not hardcoded
- **No action needed** -- this is a positive finding

### GitHub Actions: SAFE
- `pr-notify.yml`: All secrets via `${{ secrets.* }}`, PR metadata variables are safe (jq-escaped)

---

## 2. claude-tray-notifier

### Files Checked
- `.gitignore`, `package.json`, `main.js`, `preload.js`, `renderer.js`
- `lib/auth.js`, `lib/server.js`, `lib/poller.js`
- `scripts/build-and-host.sh`, `scripts/generate-token.sh`, `scripts/install-mac.sh`
- `index.html`, git history, npm audit

### Findings

**[CRITICAL] Infrastructure credentials in `scripts/build-and-host.sh`**
- File: `scripts/build-and-host.sh:27-29`
  ```
  VM_USER="<REDACTED>"
  VM_HOST="<REDACTED>"
  VM_KEY="<REDACTED>"
  ```
- Exposes: VM public IP, SSH username, SSH key path
- This is in HEAD and in git history (commit `660f76a`)
- **Remediation:**
  1. Remove the file or replace with environment variable references
  2. Run `git filter-repo` to rewrite the commit that introduced it
  3. Force-push to remove from GitHub history
  4. Alternatively, if you accept that the VM IP is public (DNS resolves REDACTED_DOMAIN to it), downgrade to MEDIUM -- but the SSH username is still a credential assist

**[HIGH] npm audit: 10 HIGH, 1 MODERATE, 2 LOW vulnerabilities**
- 13 total vulnerabilities in dependencies
- Electron-based app with `electron@^33.0.0` and `electron-builder@^25.0.0`
- Electron apps have a large attack surface; HIGH vulns in Electron dependencies are more concerning than in a static frontend
- **Remediation:** Run `npm audit fix` or pin to patched Electron version

**[MEDIUM] innerHTML usage in `renderer.js` -- MITIGATED**
- File: `renderer.js:24,28,58`
- Uses `innerHTML` to render notification cards, but all dynamic content passes through `escapeHtml()` (line 55-58) which uses the safe `textContent -> innerHTML` pattern
- The `escapeHtml` function is correctly implemented
- **Residual risk:** Low. The data source is the local poller/server, not arbitrary user input. Properly escaped.

### GitHub Actions: NONE (no `.github` directory)

---

## 3. agentGuidance

### Files Checked
- `.gitignore`, `.env.example`, `CLAUDE.md`, `agent.md`, `MANIFEST.md`
- `.claude/settings.json`, `.github/workflows/pr-notify.yml`
- `hooks/post-to-discord.sh`, `hooks/post-to-wordpress.sh`, `hooks/search-wp-posts.sh`
- `guidance/wordpress-auto-posting.md`, `guidance/secrets-hygiene.md`
- `profiles/security/*`, `templates/*`, `scripts/security-scanner/*`
- Git author emails, env files, IP/URL patterns

### Findings

**[HIGH] PII: Personal email in git commit metadata**
- `git log --format="%ae" --all` reveals `REDACTED_EMAIL`
- Same systemic issue as autonomousDev
- **Remediation:** `git filter-repo` to rewrite, then force-push

**[LOW] SSH key path reference in hooks**
- `hooks/search-wp-posts.sh:23`: `SSH_KEY="${AG_SSH_KEY:-$HOME/.ssh/vm_key}"`
- `hooks/post-to-discord.sh:274`: `VM_SSH_KEY="${VM_SSH_KEY:-$HOME/.ssh/vm_key}"`
- These reference the default key path, which is a common convention. No actual credentials exposed.
- **Remediation:** Accept. The key name `vm_key` is slightly more specific than `id_rsa` but not exploitable.

**[LOW] WordPress posting hooks use env vars correctly**
- `hooks/post-to-wordpress.sh` reads `WP_USER` and `WP_APP_PASSWORD` from env, never hardcoded
- Has comprehensive redaction regex for secrets in output (lines 112-123) -- GOOD
- `.env.example` uses placeholder values only -- GOOD

### GitHub Actions: SAFE
- `pr-notify.yml`: All secrets properly referenced via `${{ secrets.* }}`

### Positive Findings
- `.gitignore` covers `.env`, `.env.local`
- `agent.md` line 4 has explicit warning: "THIS IS A PUBLIC REPOSITORY. Never commit secrets..."
- `guidance/secrets-hygiene.md` exists with comprehensive detection patterns
- `scripts/security-scanner/` exists for automated scanning

---

## 4. ChatGPTCompletionChime

### Files Checked
- `.gitignore`, `CLAUDE.md`, `package.json`, `package-lock.json`
- `script.js`, `fsm.js`, `fsm.test.js`, `vitest.config.js`
- `.claude/settings.json`
- Git author emails, npm audit

### Findings

**[HIGH] PII: Personal email in git commit metadata**
- `git log --format="%ae" --all` reveals `REDACTED_EMAIL`
- Same systemic issue
- **Remediation:** `git filter-repo` to rewrite

### Positive Findings
- `.gitignore` covers `.env`, `.env.*`, `*.pem`, `*.key`, `credentials.json` -- comprehensive
- npm audit: 0 vulnerabilities -- clean
- No secrets, no API calls, no network requests in code (pure DOM manipulation userscript)
- `script.js` is a self-contained Tampermonkey userscript with no external dependencies or auth

---

## 5. groceryGenius

### Files Checked
- `.gitignore`, `.env.example`, `CLAUDE.md`, `context.md`, `deploy.sh`
- `.claude/settings.json`, `.github/workflows/ci.yml`, `.github/workflows/pr-notify.yml`
- `server/index.ts`, `server/auth.ts`, `server/routes.ts`, `server/storage.ts`
- `server/lib/geocoding.ts`, `shared/schema.ts`
- `client/src/hooks/use-auth.tsx`, `client/src/pages/auth.tsx`
- `server/__tests__/auth.test.ts`, `server/__tests__/security.test.ts`
- `package.json`, npm audit, git author emails

### Findings

**[HIGH] PII: Personal email in git commit metadata**
- `git log --format="%ae" --all` reveals `REDACTED_EMAIL`
- Also exposes Replit noreply email: `47832381-npezarro@users.noreply.replit.com`
- **Remediation:** `git filter-repo` to rewrite

**[MEDIUM] npm audit: 4 MODERATE vulnerabilities**
- This is a full-stack Node.js app with server-side components, so moderate vulns have higher impact than in pure frontend repos
- **Remediation:** Run `npm audit fix` and assess each moderate finding

**[LOW] Domain/deployment info in committed files**
- `deploy.sh:19`: `https://REDACTED_DOMAIN/grocerygenius/`
- `CLAUDE.md:17`: `REDACTED_DOMAIN/grocerygenius via Apache ProxyPass to localhost:8080`
- `context.md:3,9`: same domain references
- Reveals deployment architecture (Apache reverse proxy, PM2, port 8080)
- **Remediation:** Low risk for a public-facing app. The URL is discoverable anyway. Accept, but note that the ProxyPass architecture detail is unnecessary to commit.

### Positive Findings
- Auth implementation is **strong**: scrypt with random salt, timing-safe comparison (`server/auth.ts`)
- Input validation via Zod schemas (`validateInput` middleware)
- Helmet security headers enabled
- Session cookies: `httpOnly: true`, `sameSite: "strict"`, `secure` in production
- `SESSION_SECRET` required at startup (throws if missing)
- Password field excluded from query results (`schema.ts:240`)
- SQL injection mitigated via Drizzle ORM (parameterized queries)
- Security test suite exists (`server/__tests__/security.test.ts`)
- `.env.example` contains only placeholder values

### GitHub Actions: SAFE
- CI workflow: standard checkout + npm ci + lint + test + build
- PR notify: secrets properly referenced

---

## 6. valueSortify

### Files Checked
- `.gitignore`, `package.json`, `package-lock.json`
- `index.html`, `vite.config.js`, `tailwind.config.js`, `postcss.config.js`
- `src/App.jsx`, `src/main.jsx`, various components
- `.github/workflows/ci.yml`, `.github/workflows/pr-notify.yml`
- npm audit, git author emails

### Findings

**[HIGH] PII: Personal email in git commit metadata**
- `git log --format="%ae" --all` reveals `REDACTED_EMAIL`
- Same systemic issue
- **Remediation:** `git filter-repo` to rewrite

### Positive Findings
- npm audit: 0 vulnerabilities -- clean
- Pure client-side React app (no server, no auth, no API calls, no secrets)
- `.gitignore` covers `node_modules/`, `dist/`, `.DS_Store`, `*.local`
- No eval, innerHTML, or other dangerous patterns
- Minimal attack surface -- static sorting/ranking tool

### GitHub Actions: SAFE
- CI and PR notify workflows are standard and properly configured

---

## 7. humblechoice-oneclickclaim

### Files Checked
- `.claude/settings.json`, `CLAUDE.md`, `README.md`
- `humblechoice-oneclickclaim.user.js`
- Git author emails, .gitignore

### Findings

**[HIGH] PII: Personal email in git commit metadata**
- `git log --format="%ae" --all` reveals `REDACTED_EMAIL`
- Same systemic issue
- **Remediation:** `git filter-repo` to rewrite

**[LOW] No .gitignore file**
- Repo has no `.gitignore` at all
- Risk: if any dev tooling, IDE config, or env files are created, they could accidentally be committed
- **Remediation:** Add a basic `.gitignore` with at minimum: `.env`, `*.key`, `*.pem`, `.DS_Store`, `node_modules/`

### Positive Findings
- Userscript is clean: no API calls, no auth, no network requests
- DOM manipulation only, properly scoped to Humble Bundle domains
- Uses `textContent` (not `innerHTML`) for status messages -- safe
- `.claude/settings.json` has the standard hook pattern (acceptable)

---

## Cross-Portfolio Findings

### [SYSTEMIC HIGH] Personal email `REDACTED_EMAIL` in git metadata
- **Affected:** ALL 7 repos
- **Impact:** Personal email permanently exposed in git history on GitHub
- **Root cause:** Git config occasionally set to personal email instead of GitHub noreply
- **Remediation options:**
  1. **Accept the risk** -- the email is likely discoverable elsewhere (university alumni, etc.)
  2. **Portfolio-wide filter-repo** -- rewrite all commit authors across all 7 repos to `npezarro@users.noreply.github.com`, then force-push. This is destructive and will break any forks/references.
  3. **Hybrid** -- rewrite only for repos where the email appears in majority of commits, accept for others

### [SYSTEMIC LOW] `.claude/settings.json` with remote-exec hooks
- **Affected:** autonomousDev, ChatGPTCompletionChime, groceryGenius, humblechoice-oneclickclaim (4/7 repos)
- **Impact:** Reveals internal tooling architecture (agentGuidance repo, WordPress/Discord posting hooks)
- **Risk:** LOW -- the source repo (agentGuidance) is already public, and the hooks are fetched from there
- **Remediation:** Accept. Add `.claude/settings.json` to a global `.gitignore` template if you want to suppress it in future repos.

---

## Remediation Priority

| Priority | Finding | Effort |
|----------|---------|--------|
| P0 | claude-tray-notifier: VM IP + SSH username in `scripts/build-and-host.sh` | `git filter-repo` + force-push |
| P1 | Portfolio-wide personal email in git metadata (accept or rewrite) | Decision required |
| P2 | claude-tray-notifier: npm audit HIGH vulns | `npm audit fix` |
| P3 | groceryGenius: npm audit MODERATE vulns | `npm audit fix` |
| P4 | humblechoice-oneclickclaim: add `.gitignore` | 2 minutes |

---

*Generated by Security agent profile, 2026-04-10*
