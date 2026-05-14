# Security Experience Log

---
## 2026-03-26 | claude-usage-monitor
**Task:** Audit public GitHub repo for sensitive information before/after release
**What worked:** Systematic approach -- file listing, full git history diff, targeted regex scans for IPs, emails, secrets, infrastructure references, then cross-referencing known internal details (VM IP, hostnames) against repo content
**What didn't:** N/A -- clean repo, no issues found
**Learned:** For small repos, reading every file + git log -p --all is fast and thorough; for larger repos would need to prioritize high-signal scans first

---
## 2026-03-30 | multi-repo security scan (6 repos)
**Task:** Scan groceryGenius, valueSortify, claude-bakeoff, agentGuidance, youtubeSpeedSetAndRemember, claude-usage-monitor for secrets and sensitive info
**What worked:** Running all scan phases (secrets grep, IP grep, SSH grep, home paths, env files, key files, git history, gitignore, npm audit) as a structured sequential pipeline per repo; cross-referencing known infra details (VM hostname, usernames) against grep output to confirm real leaks vs. placeholder patterns
**What didn't:** Parallel bash calls frequently cancelled each other; sequential execution per repo was more reliable even if slower
**Learned:** The highest-signal findings in public repos tend to be in utility/ops scripts (health checks, hook scripts), not application code -- scan scripts/hooks directories with extra scrutiny. GitHub Actions ${{ secrets.X }} references are safe; inline script variables with real values are not. Personal email addresses and VM SSH usernames in shell scripts are HIGH severity PII leaks even when not obviously labeled as "secrets".

---
## 2026-03-30 | multi-repo security scan (page-reader, mic-volume-guard, reddit-bottom-sheet-blocker, GeminiCompletionChime, aisleOffersFilterClaimandTracking, markdownMakerBookmarklet)
**Task:** Full 10-phase security scan of 6 browser extension / utility repos
**What worked:** Extending grep patterns to cover PS1 files (PowerShell repos miss *.ps1 in standard JS/TS scans); fetching and reading the remote hook script to assess its actual risk rather than just flagging the remote-exec pattern blindly
**What didn't:** Standard grep patterns miss .claude/settings.json infrastructure leaks -- it's not a "secret" file by name but contains internal hostnames and auth patterns; needed explicit ls + read
**Learned:** .claude/settings.json is a high-signal file in public repos -- it frequently contains internal infra hostnames (WP_SITE URLs, API endpoints), remote-exec hooks, and session behavior that reveals internal architecture. Always explicitly scan it. Missing .gitignore in a repo that has .claude/settings.json is a LOW finding since settings.json is already committed, but signals the developer hasn't thought about what else might end up tracked.

---
## 2026-03-30 | multi-repo security scan (ChatGPTCompletionChime, rakutenOfferAutoAdder, GOGAutoRdeem, iconscribepublic, humblechoice-oneclickclaim, LIScreenshot)
**Task:** Full 10-phase security scan of 6 browser extension / userscript / React app repos
**What worked:** Checking git commit author emails explicitly -- `git log --format="%ae %an" --all` surfaces personal email leaks in metadata that content scans miss entirely. Filtering minified library files (html2canvas.min.js, xlsx.full.min.js) from secrets grep before treating hits as findings. Reading ApiKeyForm and IconGenerator directly when repo had OpenAI integration -- confirmed no hardcoded keys.
**What didn't:** Initial parallel bash calls cancelled each other; stayed sequential.
**Learned:** git commit author metadata is a consistent PII vector across all repos in a portfolio -- when a developer occasionally forgets to set privacy email in git config, the real email leaks into every commit from that session. npm audit HIGH findings in dev/build dependencies of a static frontend app are LOW runtime risk -- always assess the deployment context before severity-rating dependency vulns.

---
## 2026-05-12 | multi-repo security scan (GOGAutoRdeem, aisleOffersFilterClaimandTracking, humblechoice-oneclickclaim, rakutenOfferAutoAdder, reddit-bottom-sheet-blocker, markdownMakerBookmarklet)
**Task:** Full 10-phase security scan of 6 userscript / browser extension / bookmarklet repos
**What worked:** Reading build.sh explicitly in markdownMakerBookmarklet -- scripts remain the highest-signal target even in small repos. Correctly dismissing secret/token/password grep hits in markdownMakerBookmarklet as sanitization logic rather than actual leaks (the tool actively redacts credentials from page captures). GitHub Actions ${{ secrets.X }} references confirmed safe across all repos.
**What didn't:** N/A -- clean scan pass.
**Learned:** When a repo's grep hits for "secret/token/password" come from a credential-scrubbing function rather than credential storage, that is a POSITIVE signal (tool does the right thing), not a finding. Always read the surrounding code before filing. All 6 repos now use npezarro@users.noreply.github.com privacy email consistently -- the personal-email-leak vector seen in earlier scans has been remediated.

---
## 2026-03-30 | claude-token-tracker
**Task:** Pre-publication security audit of a CLI tool that parses Claude Code session transcripts for token usage tracking
**What worked:** Full file read + targeted grep for secrets, PII, URLs, known infra details. Cross-referencing test fixture paths against known private repo names. Checking npm audit, git history (single commit), author email, .gitignore coverage.
**What didn't:** N/A -- clean audit with only minor findings
**Learned:** Offline-only CLI tools (no network, no auth) have minimal attack surface but test data is a consistent PII vector -- developers use real paths from their environment in test fixtures and JSDoc examples. Always grep test/ for the developer's username and known private repo names specifically.

---
## 2026-03-30 | claude-token-tracker (re-audit)
**Task:** Post-publication re-audit of claude-token-tracker -- repo already pushed to public GitHub with 5 commits
**What worked:** Checking `git log -p --all` against the sensitive-identifiers list caught that the sanitization commit only cleaned HEAD but left all original sensitive data recoverable in the initial commit. Verified with `git show <commit>:<file>` to confirm exact exposure.
**What didn't:** The previous audit (same day, pre-push) rated the repo as clean because it only had one commit at the time and the sanitization hadn't happened yet -- the sensitive data was IN the only commit. The sanitization commit was made after my first audit, creating a false sense of safety.
**Learned:** A sanitization commit is NOT a remediation -- it just adds a clean layer on top while leaving the original data in git history. When a repo has been pushed to a public remote, always check `git log -p` on the remote branch, not just HEAD. The correct remediation is history rewriting (filter-repo/BFG) or repo recreation. Flag this explicitly in audit reports: "sanitization commit detected -- history rewrite required."

---
## 2026-03-31 | multi-repo security scan (claude-usage-monitor, mic-volume-guard, reddit-bottom-sheet-blocker, GeminiCompletionChime, aisleOffersFilterClaimandTracking, markdownMakerBookmarklet)
**Task:** Full 10-phase security scan of 6 public repos for secrets, PII, config exposure
**What worked:** Sequential per-repo scanning avoids bash cancellation issues. Checking git author emails separately from content grep catches the most consistent PII vector. Reading .claude/settings.json explicitly (learned from prior scans) caught infra disclosure in 4 repos.
**What didn't:** Initial gitignore check via `cat .gitignore || echo NO` chained with other commands caused false negatives due to shell short-circuit -- needed separate verification.
**Learned:** The personal email in git metadata is systemic across this portfolio (5/6 repos). Only claude-usage-monitor was clean, suggesting git config was fixed at some point but not retroactively applied. Recommend a portfolio-wide git-filter-repo pass or risk acceptance decision. .claude/settings.json exposure is also systemic (4/6 repos) and represents an ongoing pattern that needs a global .gitignore template fix.

---
## 2026-03-31 | multi-repo security scan (ChatGPTCompletionChime, rakutenOfferAutoAdder, GOGAutoRdeem, iconscribepublic, humblechoice-oneclickclaim, LIScreenshot)
**Task:** Full 10-phase security scan of 6 browser extension / userscript / React app repos (re-scan)
**What worked:** Sequential repo processing remains reliable. Excluding minified libs (html2canvas.min.js, papaparse.min.js, xlsx.full.min.js) from secrets grep immediately -- learned from previous scan of same repos. Checking git author emails explicitly caught the persistent PII leak across all repos.
**What didn't:** N/A -- clean execution leveraging prior experience patterns
**Learned:** These 6 repos have a remarkably consistent pattern: all share identical .claude/settings.json with remote-exec hooks, all lack .gitignore, and all leak the same personal email in git metadata. This suggests a portfolio-wide template issue -- fixing the template/workflow once would remediate all repos simultaneously. The absence of .gitignore across an entire portfolio is a systemic risk, not an individual repo oversight.

---
## 2026-05-12 | multi-repo security scan (ChatGPTCompletionChime, GeminiCompletionChime, youtubeSpeedSetAndRemember, LIScreenshot, iconscribepublic, claude-bakeoff)
**Task:** Full 10-phase security scan of 6 public repos
**What worked:** Inspecting named security-remediation commits directly with `git show <hash>` -- reveals exactly what was removed and whether values were real or already-redacted placeholders. This confirmed claude-bakeoff's hardcoded secrets were scrubbed to REDACTED_* before the initial push. Checking every security-fix commit message in git log (`ac69127`, `1d70199`, `8e07ed7`, `b6d90d4`) to trace the full remediation history. Filtering minified libs from secrets grep before assessing findings (LIScreenshot).
**What didn't:** N/A -- clean execution.
**Learned:** When git log shows commits named "remove hardcoded secrets" or "replace hardcoded path," always inspect those commits with `git show` to determine (a) whether real values were ever present or only placeholders, and (b) whether the removed value is still visible in the `+` side of an earlier commit. In claude-bakeoff, the `/home/npezarro/repos/groceryGenius` path appeared in the `+` diff of `b6d90d4` (the file-creation commit) and was only removed in `8e07ed7` -- making it recoverable from git history. A `$HOME` substitution in a new commit is NOT a history remediation; the hardcoded path persists in the diff of the commit that first introduced the file. npm audit moderate findings in vite/esbuild dev dependencies are LOW runtime risk for static frontend apps (iconscribepublic) -- the dev server is not exposed in production.

---
## 2026-05-12 | multi-repo security scan (claudeNet, claude-browser-agent, reddit-auto-hide, claude-usage-monitor)
**Task:** Full 10-phase security scan of 4 public repos covering a messaging server, browser automation agent, Reddit userscript, and usage CLI tool
**What worked:** Sequential per-repo scanning; all 4 repos confirmed using npezarro@users.noreply.github.com privacy email consistently -- no PII in git metadata. Reading deploy.sh in each repo confirmed all infra details (host, user, key path) are driven entirely from environment variables, not hardcoded. npm audit on claudeNet came back completely clean (0 vulns across 216 dependencies).
**What didn't:** N/A -- all 4 repos were clean
**Learned:** When token/secret grep hits all originate from auth middleware, test fixtures using synthetic test tokens, and .env.example placeholder documentation -- these are collectively POSITIVE signals that secrets are handled correctly (env-var injection, token hashing, never hardcoded). reddit-auto-hide's accessToken reads are a standard userscript pattern (reading the page's own session token to call the site's API on behalf of the logged-in user) -- not a hardcoded credential or a leak. Single-file userscripts with no .gitignore and no package.json are inherently minimal attack surface.

---
## 2026-03-31 | multi-repo security scan (groceryGenius, claude-token-tracker, agentGuidance, page-reader, valueSortify, claude-bakeoff, youtubeSpeedSetAndRemember)
**Task:** Full 10-phase security scan of 7 public GitHub repos for secrets, PII, infrastructure exposure
**What worked:** Sequential per-repo scanning (parallel still causes cancellations). Checking .claude/settings.json for remote-exec hooks. Cross-referencing git author emails across repos to identify inconsistent email hygiene. Reading .env.example files to verify they use safe placeholders.
**What didn't:** N/A -- clean execution
**Learned:** A centralized config/guidance repo is the highest-risk public repo in any portfolio -- it concentrates infrastructure details that individually are low-risk but together enable reconnaissance across the entire system. The remote-exec hook pattern (settings.json fetching and executing scripts from a central repo) creates a supply-chain risk: compromising the central repo's main branch could grant code execution in every downstream repo's agent sessions.

---
## 2026-04-01 | auto-dev security audit
**Task:** Pre-publication audit of autonomous dev agent repo (shell scripts, prompts, configs, logs, fix-checker subsystem)
**What worked:** Reading every file + git history search for webhooks found hardcoded Discord webhook URLs in [historical commit] (later moved to .env in [historical commit] but git history preserves them). Grepping for known infra identifiers caught infrastructure leakage in scripts and tracked log files. Checking git ls-files caught that tracked log files contain operational details.
**What didn't:** N/A
**Learned:** Ops-heavy repos (cron runners, deployment scripts) have fundamentally different risk profiles than application repos. The scripts themselves are the attack surface -- they contain SSH patterns, VM usernames, Discord channel IDs, bot token retrieval commands, and references to private repos. Tracked log files accumulate sensitive operational context over hundreds of runs. These need to be either gitignored or sanitized before going public. The "move secrets to .env" commit pattern is necessary but not sufficient when the hardcoded values remain in git history.

---
## 2026-04-01 | auto-dev pre-publication scrub (exact strings)
**Task:** Extract every sensitive string from auto-dev repo (HEAD + git history) for git filter-repo --replace-text scrubbing before making the repo public
**What worked:** Layered approach: (1) git log -p -S for secrets that were removed from HEAD but live in history (found webhook URLs in [historical commit]), (2) grep across current files for channel IDs/emails/VM refs, (3) reading each script file to understand context and identify dangerous lines, (4) checking tracked log files which accumulate sensitive operational context over hundreds of runs
**What didn't:** N/A -- clean systematic sweep
**Learned:** For ops-heavy repos, the replacements.txt file needs careful ordering -- more-specific replacements should be listed before less-specific ones to avoid double-replacement artifacts. Also, tracked log files are the largest surface area for sensitive string accumulation -- they should be removed from history entirely rather than trying to scrub hundreds of embedded references.

---
## 2026-04-01 | auto-dev-public post-filter-repo audit
**Task:** Verify git-filter-repo scrub of auto-dev-public repo before making it public
**What worked:** Layered audit approach: (1) current files grep, (2) git log -p -S for known secrets, (3) deep inspection of log file diffs in history which revealed secrets filter-repo missed. Cross-referencing against the original audit's findings list ensured completeness.
**What didn't:** N/A -- systematic approach caught everything
**Learned:** git-filter-repo --replace-text is insufficient when log files contain environment variable dumps from PM2/process managers. These dumps embed secrets inside deeply nested JSON structures that simple string replacement won't fully catch because replacement targets get substituted but adjacent secrets in the same JSON blob aren't in the replacement list. The fix is to remove entire log file paths from history (`--path logs/ --invert-paths`) rather than trying to scrub individual strings within them. Also: the replacements.txt file itself is a meta-secret -- it maps every original secret to its replacement, and must never be committed.

---
## 2026-04-01 | auto-dev-public final audit (round 3)
**Task:** Final security audit of auto-dev-public after two rounds of git-filter-repo, before making repo public
**What worked:** Comprehensive 10-pattern git history search + current file grep + full manual read of every script. The two rounds of filter-repo successfully cleaned all sensitive strings from git history. BOT_TOKEN hit in history was a false positive -- it appeared only as part of the REDACTED replacement text, not as an actual secret.
**What didn't:** N/A -- clean audit
**Learned:** After git-filter-repo, the replacements.txt files (the mapping of original-to-redacted values) remain in the working directory as untracked files. These are the single most dangerous artifact post-scrub -- they contain every original secret in plaintext. Always delete them before any push and add them to .gitignore as a safety net. A "BOT_TOKEN" git-log -S hit does not necessarily mean a real secret -- it can match the redacted-replacement text that contains the substring. Always read the full diff context before declaring a finding.

---
## 2026-04-01 | auto-dev
**Task:** Full pre-publication security audit of autonomous development agent repo
**What worked:** Cross-referencing the existing SCRUB-LIST.md against actual file contents and git history to verify completeness; checking git show on specific historical commits to confirm exposure; verifying .env was never committed despite being on disk
**What didn't:** N/A -- thorough audit with existing scrub list as starting point
**Learned:** When a repo already has a scrub list, audit the scrub list itself as a finding -- it contains all the secrets it documents in plaintext and must not be published. Also verify the scrub has actually been executed, not just planned. The SCRUB-LIST.md pattern is a documentation-before-action trap: the most dangerous moment is when you have a complete list of secrets in a tracked file that could accidentally get pushed.

---
## 2026-04-02 | Multi-repo security scan (browser extensions + userscripts)
**Task:** Scan 5 repos (mic-volume-guard, reddit-bottom-sheet-blocker, GeminiCompletionChime, aisleOffersFilterClaimandTracking, ChatGPTCompletionChime) for sensitive information exposure using 10-point scan checklist
**What worked:** Running all 5 repo scans in parallel for speed. Checking file listings to discover PowerShell scripts not covered by initial grep include filters. Verifying git history had no deleted secrets with broader search terms.
**What didn't:** Initial grep --include filters missed .ps1 files in mic-volume-guard. The bash `||` operator in the chained scan script caused .gitignore cat failure to mask subsequent scan outputs -- needed to fix the control flow.
**Learned:** Browser extension and userscript repos tend to be very clean because they run client-side with no backend secrets. The main risk surface is missing .gitignore files (no safety net against future accidental commits). GitHub Actions `${{ secrets.* }}` references are NOT findings -- they are the correct pattern. Always check the actual file listing to discover file types not covered by the grep include filters (e.g., .ps1, .lua, .rb).

---
## 2026-04-02 | Multi-repo security scan (5 repos)
**Task:** Comprehensive sensitive information scan across page-reader, claude-token-tracker, valueSortify, groceryGenius, auto-dev
**What worked:** Parallel scanning of all repos simultaneously, then targeted deep-dives on flagged files. Distinguishing false positives (LLM token counts, DOM password field detection) from real findings by reading surrounding context. Cross-referencing .gitignore coverage against actual env var usage patterns.
**What didn't:** N/A -- systematic approach was efficient
**Learned:** The biggest risk in ops-heavy repos post-scrub is not residual secrets but operational context files that map credential locations, service architecture, and auth flows. Context documentation written for AI agents to understand a system is equally useful to attackers. A repo can pass all secret-scanning tools while still containing a complete attack playbook in its documentation. Recommend treating credential-location-mapping docs as sensitive even when they contain no actual secrets.

---
## 2026-04-02 | Multi-repo security scan (5 repos)
**Task:** Scan claude-bakeoff, agentGuidance, youtubeSpeedSetAndRemember, markdownMakerBookmarklet, claude-usage-monitor for sensitive information exposure
**What worked:** Running all 10 scan patterns per repo in a single shell command, then parallelizing across all 5 repos simultaneously. Second pass to read specific flagged files for context (distinguishing real secrets from variable names/redaction logic). The markdownMakerBookmarklet "password/token/credential" hits were all false positives from its HTML redaction code — reading the source confirmed this.
**What didn't:** N/A — systematic approach was clean
**Learned:** An orchestration/guidance repo is the highest-risk repo in a portfolio because it concentrates infrastructure references across hooks and guidance docs. The hooks directory is the primary attack surface for any repo that contains deployment and notification scripts. Browser extension repos and client-side tools tend to be clean because they have no server-side secrets by design.

---
## 2026-04-02 | Multi-repo security scan (5 public repos)
**Task:** Comprehensive 10-point security scan of rakutenOfferAutoAdder, GOGAutoRdeem, iconscribepublic, humblechoice-oneclickclaim, LIScreenshot
**What worked:** Parallel scanning of all repos simultaneously, then drilling into findings. Excluding minified files (html2canvas.min.js) early prevented noise. Checking git ls-files to understand what's tracked vs what's on disk.
**What didn't:** N/A -- clean systematic sweep
**Learned:** Most small browser extension / userscript repos are README-only or have minimal code with no server-side secrets. The highest-risk pattern in client-side BYOK apps is localStorage + DOM rendering of API keys -- not a "leak" per se but an attack surface for XSS/extension-based exfiltration. Missing .gitignore in Node projects is a higher-priority finding than in static repos because the blast radius of an accidental commit is much larger (node_modules, .env, dist/).

---
## 2026-04-02 | Multi-repo private-content OPSEC audit (20 public repos)
**Task:** Scan all 20 public repos for any content revealing the owner is job hunting -- HEAD files, commit messages, git diff history, branch names
**What worked:** Systematic parallel scanning with grep patterns, then deep-diving into high-signal repos (agentGuidance, auto-dev, page-reader). Filtering false positives (application/json, "web application", audio.resume()) before reporting. Checking deleted files via git show on parent commits.
**What didn't:** git show COMMIT~1:path syntax failed on some merge commits; needed to use COMMIT^ instead (also failed on boundary commits where file was added, not present in parent)
**Learned:** The biggest OPSEC gap is not in current HEAD but in git history. A file can be "removed" from the repo but every version is still recoverable from any clone. Branch names and commit messages are particularly sticky -- they survive even after the files they reference are deleted. A scrub of file contents can still leave behind: (1) guidance files in HEAD, (2) revealing branch names, (3) commit messages, (4) recoverable deleted files in history, and (5) log entries referencing private repos. All repos in a portfolio need to be checked -- it's common for some to be missed in a scrub pass.

---
## 2026-04-04 | MCP server supply chain security audit
**Task:** Audit @piotr-agier/google-drive-mcp and @playwright/mcp packages used as Claude Code MCP servers
**What worked:** Cross-referencing npm registry API data (maintainers, download counts, publish dates) with GitHub profiles and Socket.dev analysis. Checking the actual file permissions on OAuth credentials. Comparing the community package against the official Anthropic alternative to understand why the user chose it (write capabilities). The Docker MCP supply chain attack blog post provided concrete threat scenarios.
**What didn't:** npmjs.com and socket.dev web pages returned 403 on WebFetch -- had to fall back to the npm registry JSON API directly, which actually gave more structured data.
**Learned:** The npx -y pattern for MCP servers is the highest-risk configuration choice -- it combines auto-install, no version pinning, no lockfile, and full env var access (including credential paths). Single-maintainer packages with OAuth access are a particularly dangerous combination because one compromised npm token gives attackers access to every user's Google account. The mitigation priority order is: (1) pin versions, (2) install locally with lockfile, (3) monitor for official alternatives. Also: always check file permissions on credential files passed via MCP env config -- the default umask often leaves them world-readable.

---
## 2026-04-05 | Remote browser agent security considerations (freeGames)
**Task:** Review security implications of the remote browser agent pattern (TM script polling server for arbitrary commands)
**What worked:** The install-once pattern means the TM script never changes, reducing the attack surface of script updates. Server-side orchestrator keeps all flow logic centralized and auditable. The `eval` command for Epic iframe access is scoped to specific checkout flows.
**Learned:** The remote agent pattern (thin TM script + server orchestrator) has two key security trade-offs: (1) the `eval` command allows arbitrary JS execution in the browser context, which is powerful but should be limited to authenticated server commands only; (2) the polling interval (3s) means a compromised server could inject commands into any matched domain. Mitigation: ensure the server API requires authentication, and the TM script only accepts commands from the known server origin. The CAPTCHA bypass works because the browser has legitimate fingerprints, not because of any exploit -- this is acceptable for personal automation on owned accounts.

---
## 2026-04-05 | AI chat export PII exposure (llm-tasks)
**Task:** Identified and documented PII risk from AI chat export files committed to public repos
**What worked:** Emergency removal of Gemini exports containing sensitive sidebar titles (medical/psychiatric references, tax details) plus email addresses. Added `Reference Files/` to .gitignore to prevent recurrence. Files relocated to privateContext for safe agent access.
**Learned:** AI chat exports are a novel PII attack surface that traditional secret scanners miss. The sidebar content in exports (Gemini, ChatGPT) includes titles from ALL conversations, not just the exported one. A single export file can leak dozens of sensitive topics. Unlike credentials, these can't be "rotated" -- the information is permanently exposed once pushed. Prevention: .gitignore upload directories by default in any repo where users might paste reference materials. Detection: grep for common export patterns (chat titles, email metadata) in pre-commit hooks.

---
## 2026-04-06 | Portable pre-commit hook for public repos (agentGuidance)
**Task:** Implemented and documented a portable pre-commit hook that scans staged diffs for sensitive identifiers before allowing commits to public repos
**What worked:** Tracked hook in `hooks/git-pre-commit` with `scripts/install-hooks.sh` installer. Hook pipes `git diff --cached` through `security-scan.sh` and blocks on BLOCKED output. Graceful degradation: if security-scan.sh isn't available (no privateContext), it warns but allows the commit — prevents blocking external contributors.
**Learned:** Automated pre-commit scanning catches leaks that manual checklists miss, especially during bulk edits and security redaction work (the same session that added this hook saw an accidental file deletion from an overly broad `git add`). The hook-as-tracked-file pattern (vs .git/hooks/ only) means the hook survives clones and is version-controlled. The install script is needed because git doesn't auto-install hooks from tracked files.

---
## 2026-05-12 | multi-repo security scan (agentGuidance, autonomousDev, page-reader, browser-agent, groceryGenius, claude-tray-notifier)
**Task:** Full 10-phase security scan of 6 public GitHub repos for secrets, PII, infra exposure
**What worked:** Sequential repo scanning remained reliable. Checking fix-checker/config.json in autonomousDev directly (committed JSON with REDACTED placeholders) confirmed proper scrubbing. Reading deploy.sh and build-and-host.sh in browser-agent and claude-tray-notifier confirmed all infra credentials are env-var-driven with no hardcoded values. Verifying git author emails across all repos -- all consistently use the noreply GitHub address.
**What didn't:** N/A -- clean execution
**Learned:** The autonomousDev repo is a successfully scrubbed ops-heavy repo: all infra references (VM host, channel IDs, repo root paths, bot token commands) are replaced with REDACTED_ prefixed placeholders. The claude-tray-notifier install-mac.sh contains an explicit reference to "privateContext/claude-tray-token" -- this discloses the existence of a private credential-storage repository but not any actual secret. This is a LOW finding (architecture disclosure) not a credential leak. repos that use REDACTED_ prefixes consistently throughout are easier to audit than those that use generic examples.

---
## 2026-05-12 | multi-repo security scan (portfolio, mic-volume-guard, valueSortify, manchu-translator, claude-token-tracker)
**Task:** Full 10-phase security scan of 5 public repos spanning a resume repo, PowerShell utility, React app, Node.js backend, and TypeScript CLI
**What worked:** Sequential per-repo scanning. Checking git log --oneline for high-signal commit messages ("Redact infrastructure details") that indicate prior exposure, then using `git show <commit>^:<file>` to confirm exactly what was in the pre-redaction version. Extending grep to cover .ps1 files for the PowerShell repo. Reading ecosystem.config.js files directly for port/process-name disclosure in git history.
**What didn't:** N/A -- clean systematic pass
**Learned:** A "Redact infrastructure details" commit message is an immediate red flag -- always inspect the pre-redaction commit to confirm what was exposed. In this case the pre-redaction context.md contained real port numbers (3110/3111), PM2 process names, reverse-tunnel SSH flags (-R 3111:127.0.0.1:3111), and Apache vhost config file path -- all now in public git history within --depth 50. The VM hostname itself used a placeholder even before redaction, so the most sensitive detail was never committed. Distinction matters: infra topology/ports in git history = MEDIUM overshare; actual hostname/credentials = HIGH/CRITICAL. npm audit 0-vuln results across all three Node repos confirms dependency hygiene is sound.

---
## 2026-05-14 | multi-repo security scan (claude-tray-notifier, GOGAutoRdeem, aisleOffersFilterClaimandTracking, humblechoice-oneclickclaim, rakutenOfferAutoAdder, reddit-bottom-sheet-blocker, markdownMakerBookmarklet)
**Task:** Full 13-phase security scan of 7 public repos (Electron app, browser extensions, userscripts, bookmarklet)
**What worked:** Sequential per-repo scanning with all 13 phases in single bash commands. Reading flagged files in context (build-and-host.sh, install-mac.sh, sessions.test.js) to distinguish real findings from false positives. Correctly identifying markdownMakerBookmarklet secret/token/password hits as credential-scrubbing logic. All 7 repos use noreply GitHub email consistently -- the personal email leak from earlier scans has been fully remediated across this batch.
**What didn't:** N/A -- clean systematic pass
**Learned:** This portfolio batch is remarkably clean. All repos have proper .gitignore coverage (.env, .pem, .key, credentials.json, .claude/), all use env-var-driven infrastructure (no hardcoded hosts/keys), all use privacy email in git metadata, and no .claude/settings.json is committed in any of them. The only findings are two moderate postcss dependency vulns (dev-only, low runtime risk) and the install-mac.sh privateContext reference (architecture disclosure, not a credential leak). The systematic remediation work from prior audits has clearly paid off -- these repos show consistent application of security hygiene patterns across the entire portfolio.

---
## 2026-05-14 | multi-repo security scan (agentGuidance, autonomousDev, groceryGenius, browser-agent, page-reader, portfolio, cli-orchestrator)
**Task:** Full 13-phase security scan of 7 public repos covering secret patterns, IP addresses, SSH commands, home paths, .env files, key files, .gitignore gaps, env var documentation, git history for deleted secrets, npm audit, and CORS/debug configs.
**What worked:** The pre-redaction commit inspection pattern continues to be the highest-value technique. browser-agent commit 467ad49 ("Scrub hardcoded infrastructure details for public release") exposed that deploy.sh, sync-tm-scripts.sh, browser-cli.sh, and agent-server.js all contained hardcoded SSH username, VM host, and WSL paths before the scrub -- all recoverable via `git show <commit>^:<file>`. autonomousDev commit d7a693f similarly exposed PM2 process-to-repo mappings and full repo lists in git history, but repos_root was always REDACTED_REPOS_ROOT (never a real path). The `.claude/settings.json` deletion in autonomousDev revealed a curl-pipe-bash pattern for session hooks -- architecture disclosure but not a credential leak. npm audit across all 4 Node repos returned 0 vulnerabilities.
**What didn't:** N/A -- systematic execution
**Learned:** browser-agent has the most significant git history exposure of the 7 repos: real SSH username, real VM hostname (in SSH connection strings), hardcoded WSL path with local username, and hardcoded deploy-user home paths -- all in public git history. The current HEAD is clean (env-var driven) but history remediation (e.g., git filter-branch or BFG) has not been performed. The CORS `Access-Control-Allow-Origin: *` in browser-agent is intentional for a Tampermonkey/extension client architecture but should still be documented as an accepted risk. portfolio is the only repo with NO .gitignore -- static site repos still need one to prevent accidental .env or credential commits. cli-orchestrator .gitignore is missing *.pem and *.key entries.

---
## 2026-05-14 | multi-repo security scan (ChatGPTCompletionChime, GeminiCompletionChime, youtubeSpeedSetAndRemember, LIScreenshot, iconscribepublic, claude-bakeoff, mic-volume-guard)
**Task:** Full 13-phase security scan of 7 public repos covering browser extensions, userscripts, a React BYOK app, a shell-based bakeoff framework, and a PowerShell utility
**What worked:** Parallel scanning of all 7 repos simultaneously (with || true to prevent exit-code cancellation). Deep-diving into iconscribepublic ApiKeyForm/IconGenerator/ReferenceImageGallery chain to trace API key lifecycle (input -> sessionStorage -> fetch header -> DOM rendering in error states). Inspecting claude-bakeoff git history commit ac69127 ("Remove hardcoded secrets and SSH paths") to determine what was exposed pre-cleanup -- confirmed REDACTED_* placeholders were used before the initial push, but SSH token-fetch commands (REDACTED_SSH_COMMAND) and Discord IDs (REDACTED_CHANNEL_ID, REDACTED_BOT_ID, REDACTED_WEBHOOK_URL) were present and then removed.
**What didn't:** /tmp/security-scan/ was cleaned up mid-session (temp directory lifecycle), but all scan data was already captured before cleanup.
**Learned:** iconscribepublic's ReferenceImageGallery renders the user's OpenAI API key in the DOM (with show/hide toggle) during error states -- this is a MEDIUM finding because it creates an XSS exfiltration surface for browser extensions that can read DOM content. The key is stored in sessionStorage (better than localStorage -- cleared on tab close) but still accessible to any JS on the page. claude-bakeoff is the best-remediated ops repo in this batch: proper .env.example with placeholder values, .gitignore covering all secret patterns, secrets sourced from external ~/.config/ path, and the pre-cleanup commit used REDACTED_ prefixes consistently. The 4 browser extension/userscript repos (ChatGPTCompletionChime, GeminiCompletionChime, youtubeSpeedSetAndRemember, LIScreenshot) are all clean -- client-side-only with no secrets by design, proper .gitignore, 0 npm vulns, no git history findings.
