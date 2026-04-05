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
## 2026-03-30 | claude-token-tracker
**Task:** Pre-publication security audit of a CLI tool that parses Claude Code session transcripts for token usage tracking
**What worked:** Full file read + targeted grep for secrets, PII, URLs, known infra details. Cross-referencing test fixture paths against known private repo names. Checking npm audit, git history (single commit), author email, .gitignore coverage.
**What didn't:** N/A -- clean audit with only minor findings
**Learned:** Offline-only CLI tools (no network, no auth) have minimal attack surface but test data is a consistent PII vector -- developers use real paths from their environment in test fixtures and JSDoc examples. Always grep test/ for the developer's username and known private repo names specifically.

---
## 2026-03-30 | claude-token-tracker (re-audit)
**Task:** Post-publication re-audit of claude-token-tracker -- repo already pushed to public GitHub with 5 commits
**What worked:** Checking `git log -p --all` against the sensitive-identifiers list caught that the sanitization commit (d0693c4) only cleaned HEAD but left all original sensitive data recoverable in the initial commit (4b85b97). Verified with `git show <commit>:<file>` to confirm exact exposure.
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
## 2026-03-31 | multi-repo security scan (groceryGenius, claude-token-tracker, agentGuidance, page-reader, valueSortify, claude-bakeoff, youtubeSpeedSetAndRemember)
**Task:** Full 10-phase security scan of 7 public GitHub repos for secrets, PII, infrastructure exposure
**What worked:** Sequential per-repo scanning (parallel still causes cancellations). Checking .claude/settings.json for remote-exec hooks. Cross-referencing git author emails across repos to identify inconsistent email hygiene. Reading .env.example files to verify they use safe placeholders.
**What didn't:** N/A -- clean execution
**Learned:** agentGuidance as the centralized config hub is the highest-risk public repo in the portfolio -- it's the single place where infrastructure details (usernames, private repo names, credential storage paths, VM details) concentrate. A single compromise of this repo enables reconnaissance across the entire portfolio. The remote-exec hook pattern (.claude/settings.json fetching and executing scripts from agentGuidance) creates a supply-chain risk: compromising agentGuidance's main branch would grant code execution in every downstream repo's Claude sessions.

---
## 2026-04-01 | autonomousDev security audit
**Task:** Pre-publication audit of autonomous dev agent repo (shell scripts, prompts, configs, logs, fix-checker subsystem)
**What worked:** Reading every file + git history search for webhooks found hardcoded Discord webhook URLs in commit eec1012 (later moved to .env in 9b5f3e7 but git history preserves them). Grepping for known infra identifiers (generatedByTermius, pezant-vm, channel IDs) caught infrastructure leakage in scripts and tracked log files. Checking git ls-files caught that progress.md and failures.md (large tracked logs) contain operational details.
**What didn't:** N/A
**Learned:** Ops-heavy repos (cron runners, deployment scripts) have fundamentally different risk profiles than application repos. The scripts themselves are the attack surface -- they contain SSH patterns, VM usernames, Discord channel IDs, bot token retrieval commands, and references to private repos. Tracked log files (progress.md, failures.md) accumulate sensitive operational context over hundreds of runs. These need to be either gitignored or sanitized before going public. The "move secrets to .env" commit pattern is necessary but not sufficient when the hardcoded values remain in git history.

---
## 2026-04-01 | autonomousDev pre-publication scrub (exact strings)
**Task:** Extract every sensitive string from autonomousDev repo (HEAD + git history) for git filter-repo --replace-text scrubbing before making the repo public
**What worked:** Layered approach: (1) git log -p -S for secrets that were removed from HEAD but live in history (found both webhook URLs in commit eec1012), (2) grep across current files for channel IDs/emails/VM refs, (3) reading each script file to understand context (the bot token retrieval SSH command in fix-checker/run.sh:255 is the most dangerous single line), (4) checking tracked log files which accumulate sensitive operational context over hundreds of runs
**What didn't:** N/A -- clean systematic sweep
**Learned:** For ops-heavy repos, the replacements.txt file needs careful ordering -- `/home/generatedByTermius/centralDiscord/.env` contains both the VM path AND the private repo name, so more-specific replacements should be listed before less-specific ones to avoid double-replacement artifacts. Also, tracked log files (progress.md at 262KB, failures.md) are the largest surface area for sensitive string accumulation -- they should be removed from history entirely rather than trying to scrub hundreds of embedded references. The `centralDiscord` replacement is safe in this repo but would be dangerous in a repo that uses that string in other contexts.

---
## 2026-04-01 | autonomousDev-public post-filter-repo audit
**Task:** Verify git-filter-repo scrub of autonomousDev-public repo before making it public
**What worked:** Layered audit approach: (1) current files grep, (2) git log -p -S for known secrets, (3) deep inspection of log file diffs in history which revealed secrets filter-repo missed. Cross-referencing against the original audit's findings list ensured completeness.
**What didn't:** N/A -- systematic approach caught everything
**Learned:** git-filter-repo --replace-text is insufficient when log files contain environment variable dumps from PM2/process managers. These dumps embed secrets (bot tokens, webhook URLs, channel IDs) inside deeply nested JSON structures that simple string replacement won't fully catch because the replacement targets (like "generatedByTermius") get replaced but adjacent secrets in the same JSON blob (like DISCORD_BOT_TOKEN values) aren't in the replacement list. The fix is to remove entire log file paths from history (`--path logs/ --invert-paths`) rather than trying to scrub individual strings within them. Also: the replacements.txt file itself is a meta-secret -- it maps every original secret to its replacement, and must never be committed.

---
## 2026-04-01 | autonomousDev-public final audit (round 3)
**Task:** Final security audit of autonomousDev-public after two rounds of git-filter-repo, before making repo public
**What worked:** Comprehensive 10-pattern git history search + current file grep + full manual read of every script. The two rounds of filter-repo successfully cleaned all sensitive strings from git history. BOT_TOKEN hit in history was a false positive -- it appeared only as part of the REDACTED replacement text, not as an actual secret.
**What didn't:** N/A -- clean audit
**Learned:** After git-filter-repo, the replacements.txt files (the mapping of original-to-redacted values) remain in the working directory as untracked files. These are the single most dangerous artifact post-scrub -- they contain every original secret in plaintext. Always delete them before any push and add them to .gitignore as a safety net. A "BOT_TOKEN" git-log -S hit does not necessarily mean a real secret -- it can match the redacted-replacement text that contains the substring. Always read the full diff context before declaring a finding.

---
## 2026-04-01 | autonomousDev
**Task:** Full pre-publication security audit of autonomous development agent repo
**What worked:** Cross-referencing the existing SCRUB-LIST.md against actual file contents and git history to verify completeness; checking git show on specific historical commits to confirm webhook exposure; verifying .env was never committed despite being on disk
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
**Task:** Comprehensive sensitive information scan across page-reader, claude-token-tracker, valueSortify, groceryGenius, autonomousDev
**What worked:** Parallel scanning of all repos simultaneously, then targeted deep-dives on flagged files. Distinguishing false positives (LLM token counts, DOM password field detection) from real findings by reading surrounding context. Cross-referencing .gitignore coverage against actual env var usage patterns.
**What didn't:** N/A -- systematic approach was efficient
**Learned:** The biggest risk in ops-heavy repos (like autonomousDev) post-scrub is not residual secrets but operational context files that map credential locations, service architecture, and auth flows. These "context.md" files are written for AI agents to understand the system, which means they are equally useful to attackers. A repo can pass all secret-scanning tools while still containing a complete attack playbook in its documentation. Recommend treating credential-location-mapping docs as sensitive even when they contain no actual secrets.

---
## 2026-04-02 | Multi-repo security scan (5 repos)
**Task:** Scan claude-bakeoff, agentGuidance, youtubeSpeedSetAndRemember, markdownMakerBookmarklet, claude-usage-monitor for sensitive information exposure
**What worked:** Running all 10 scan patterns per repo in a single shell command, then parallelizing across all 5 repos simultaneously. Second pass to read specific flagged files for context (distinguishing real secrets from variable names/redaction logic). The markdownMakerBookmarklet "password/token/credential" hits were all false positives from its HTML redaction code — reading the source confirmed this.
**What didn't:** N/A — systematic approach was clean
**Learned:** agentGuidance is the highest-risk repo because it's the orchestration layer — it contains SSH connection strings, personal email addresses, VM usernames, production domains, credential file paths, and Discord channel IDs spread across hooks and guidance docs. The hooks directory (post-to-discord.sh, post-to-wordpress.sh, hook-health-check.sh) is the primary attack surface. Browser extension repos (youtubeSpeedSetAndRemember) and client-side tools (markdownMakerBookmarklet) tend to be clean because they have no server-side secrets by design.

---
## 2026-04-02 | Multi-repo security scan (5 public repos)
**Task:** Comprehensive 10-point security scan of rakutenOfferAutoAdder, GOGAutoRdeem, iconscribepublic, humblechoice-oneclickclaim, LIScreenshot
**What worked:** Parallel scanning of all repos simultaneously, then drilling into findings. Excluding minified files (html2canvas.min.js) early prevented noise. Checking git ls-files to understand what's tracked vs what's on disk.
**What didn't:** N/A -- clean systematic sweep
**Learned:** Most small browser extension / userscript repos are README-only or have minimal code with no server-side secrets. The highest-risk pattern in client-side BYOK apps is localStorage + DOM rendering of API keys -- not a "leak" per se but an attack surface for XSS/extension-based exfiltration. Missing .gitignore in Node projects is a higher-priority finding than in static repos because the blast radius of an accidental commit is much larger (node_modules, .env, dist/).

---
## 2026-04-02 | Multi-repo private-content OPSEC audit (20 public repos)
**Task:** Scan all 20 public repos for any content revealing the owner is job hunting -- HEAD files, commit messages, git diff history, branch names
**What worked:** Systematic parallel scanning with grep patterns, then deep-diving into high-signal repos (agentGuidance, autonomousDev, page-reader). Filtering false positives (application/json, "web application", audio.resume()) before reporting. Checking deleted files via git show on parent commits.
**What didn't:** git show COMMIT~1:path syntax failed on some merge commits; needed to use COMMIT^ instead (also failed on boundary commits where file was added, not present in parent)
**Learned:** The biggest OPSEC gap is not in current HEAD but in git history. A file can be "removed" from the repo but every version is still recoverable from any clone. Branch names (claude/private-content-url-block, claude/email-digest-private-guidance) and commit messages are particularly sticky -- they survive even after the files they reference are deleted. The agentGuidance repo had a proper scrub of file contents but left behind: (1) the full private-guidance.md guidance file in HEAD, (2) branch names, (3) commit messages, (4) recoverable deleted files in history, and (5) a cron log referencing the private private-repo repo. The autonomousDev repo was missed in the scrub entirely -- config.json and repos.conf still reference private-repo and private-linkedin-tool in HEAD.

---
## 2026-04-04 | MCP server supply chain security audit
**Task:** Audit @piotr-agier/google-drive-mcp and @playwright/mcp packages used as Claude Code MCP servers
**What worked:** Cross-referencing npm registry API data (maintainers, download counts, publish dates) with GitHub profiles and Socket.dev analysis. Checking the actual file permissions on OAuth credentials. Comparing the community package against the official Anthropic alternative to understand why the user chose it (write capabilities). The Docker MCP supply chain attack blog post provided concrete threat scenarios.
**What didn't:** npmjs.com and socket.dev web pages returned 403 on WebFetch -- had to fall back to the npm registry JSON API directly, which actually gave more structured data.
**Learned:** The npx -y pattern for MCP servers is the highest-risk configuration choice -- it combines auto-install, no version pinning, no lockfile, and full env var access (including credential paths). Single-maintainer packages with OAuth access are a particularly dangerous combination because one compromised npm token gives attackers access to every user's Google account. The mitigation priority order is: (1) pin versions, (2) install locally with lockfile, (3) monitor for official alternatives. Also: always check file permissions on credential files passed via MCP env config -- the default umask often leaves them world-readable.
