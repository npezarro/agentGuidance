# Secrets Hygiene

Rules for handling secrets, credentials, and infrastructure details in code — especially in public repositories.

## The Core Rule

**Never commit secrets, infrastructure specifics, or internal paths to a repository that is (or could become) public.** This includes:
- API keys, tokens, webhook URLs
- IP addresses, hostnames, SSH aliases
- Internal directory paths (home directories, deploy paths)
- SSH commands that reveal server structure
- Architecture docs with specific IPs, ports, or usernames

## Never Echo Secrets to Conversation Output

When reading credential files (privateContext, .env, etc.), confirm you found them by name but **never include actual values in your response text**. Reference credentials by variable name only (e.g., "Got the SnapTrade credentials from privateContext") — the user already knows the values, and echoing them to chat creates unnecessary exposure in conversation logs and exports.

**Why:** Credentials should stay in files and env vars. Chat output gets logged, exported, and sometimes shared. A real incident prompted this rule — it's a habit violation, not a theoretical concern.

## Where Secrets Go

Secrets live in **external .env files** outside the repository:

```
~/.config/<project-name>/.env    # per-project secrets
~/.cache/<tool>-token            # cached credentials
```

Never in:
- `config.yaml`, `config.json`, or any committed config file
- Shell scripts (no hardcoded `ssh user@1.2.3.4` commands)
- Documentation or READMEs
- Inline defaults in code (e.g., `HOST="${VAR:-1.2.3.4}"`)

## How to Reference Secrets in Code

```bash
# GOOD: Source from external file, fail loudly if missing
ENV_FILE="${MY_ENV_FILE:-$HOME/.config/myproject/.env}"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"
HOST="${MY_HOST:?MY_HOST not set — see .env.example}"

# GOOD: Read from cache, no SSH fallback that reveals paths
get_token() {
  [ -n "${MY_TOKEN:-}" ] && echo "$MY_TOKEN" && return
  [ -f "$HOME/.cache/my-token" ] && cat "$HOME/.cache/my-token" && return
  return 1
}

# BAD: Hardcoded IP
HOST="35.x.x.x"

# BAD: SSH command revealing internal structure
token=$(ssh myhost 'grep TOKEN /path/to/.env')
```

## Every Repo Must Have

1. **`.gitignore`** — includes `.env`, `.env.local`, `*.pem`, `credentials.json`
2. **`.env.example`** — documents required variables with placeholder values
3. **No inline defaults that leak specifics** — use `YOUR_VALUE` or `:?` to require the var

## Sensitive Identifiers (Non-Secret Leaks)

Not all leaks are credentials. Usernames, private repo names, internal hostnames, and home directory paths also reveal infrastructure layout and should not appear in public repos — including in test fixtures, JSDoc examples, and documentation.

Before making a repo public or writing example code in a public repo:
1. Check the **private reference database** for identifiers that must be sanitized
2. Replace real usernames, paths, and private project names with generic alternatives
3. Verify that repo names referenced in tests/docs are actually public

The reference database lists every known private identifier and its safe replacement. If you don't have access to it, use generic placeholders: `/home/user/`, `myProject`, `example.com`.

## AI Chat Export Files

AI chat exports (Gemini, ChatGPT, Claude) are a high-risk PII vector. Export files routinely contain:
- **Sidebar chat titles** with sensitive topics (medical records, financial details, legal matters)
- **Email addresses** embedded in conversation metadata
- **Personal names and identifiers** from prior conversations

Never commit raw AI chat exports to any repository. If reference material from an AI conversation is needed:
1. Extract only the relevant content into a new file
2. Scrub any sidebar/metadata content before committing
3. Add the export directory to `.gitignore` (e.g., `Reference Files/`)
4. If the full export is needed for agent access, store it in `privateContext/`

This pattern caused a real incident: Gemini exports with medical/psychiatric chat titles were committed to a public repo and had to be emergency-removed (2026-04-05).

## Automated Security Hooks (Pre-Commit + Pre-Push)

All public repos MUST have both pre-commit and pre-push hooks installed. These scan for sensitive identifiers before code reaches the remote.

### Hook Files

- `hooks/git-pre-commit` — scans staged diffs at commit time
- `hooks/git-pre-push` — scans all commits being pushed (catches amended commits, rebases, cherry-picks that bypassed pre-commit)
- `hooks/install-hooks.sh` — installs both hooks to one or all public repos

### How They Work

- **Pre-commit:** Pipes `git diff --cached` through `security-scan.sh`. Blocks if any sensitive identifier is found.
- **Pre-push:** Determines the commit range being pushed, checks if the repo is public (via `gh repo view`), and scans the full diff. Only enforces on public repos — private repos pass through.

### Installation

```bash
# Install to all local public repos + set up global git template
bash ~/repos/agentGuidance/hooks/install-hooks.sh --all-public

# Install to a single repo
bash ~/repos/agentGuidance/hooks/install-hooks.sh ~/repos/myrepo
```

The `--all-public` flag also configures `~/.git-templates/hooks/` as the global git template directory, so any newly cloned repo automatically gets both hooks.

### For Agents

When creating a new public repo or cloning one that doesn't have hooks yet, run:
```bash
bash ~/repos/agentGuidance/hooks/install-hooks.sh ~/repos/<repo-name>
```

**Why:** The claude-tray-notifier incident (2026-04-10) showed that hardcoded VM credentials survived in a public repo for months because only pre-commit hooks existed on one repo. Pre-push hooks on all public repos would have caught this at push time regardless of which repo it happened in.

### Legitimate `--no-verify` for Security Redactions

The hooks scan the full `git diff`, including removed lines. When you're *removing* a sensitive identifier (redacting), the removed line still contains the identifier and triggers the hook. This is a known catch-22: the hook blocks the very commit that fixes the problem.

**`--no-verify` is acceptable** when all of these are true:
1. The commit is purely a security redaction (removing or replacing sensitive identifiers)
2. The removed lines are the only hook violations (no new identifiers being added)
3. The commit message explicitly states the bypass reason (e.g., "Security remediation: --no-verify used because pre-commit hook flags the removal lines")

This pattern was validated across 7+ repos during the 2026-05 infrastructure redaction sweep (claude-tray-notifier, claudeNet, groceryGenius, manchu-translator, valueSortify, youtubeSpeedSetAndRemember, claude-bakeoff, agentGuidance).

## Pre-Commit Checklist (Manual Fallback)

When the automated hook isn't installed, verify before committing to any public repo:

1. `grep -rn 'ssh.*@\|BEGIN.*KEY\|api.key\|webhook' .` — no secrets in staged files
2. No IP addresses in code (check: `grep -rn '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' .`)
3. No absolute paths to home directories
4. No private repo names or usernames in test fixtures, docs, or comments (check against the private reference database)
5. `.gitignore` covers `.env*` files
6. Config files use environment variables, not hardcoded values

## Architecture Documentation

When documenting internal systems in a public repo:
- Describe the **pattern** (e.g., "reverse SSH tunnel to local machine"), not the **specifics** (e.g., "ssh -p 2222 user@1.2.3.4")
- Use generic terms: "cloud VM", "local machine", "the bot" — not hostnames or IPs
- Keep incident details focused on the **lesson**, not the infrastructure layout
- If specifics are needed, put them in a private repo or local notes

## Infrastructure Overshare in Context Files

`context.md`, `CLAUDE.md`, and deploy scripts in public repos must NOT include:
- **VM filesystem paths** (`/var/www/...`, `/opt/...`, `/home/deploy/...`)
- **PM2 process names and port assignments** (maps the full service architecture)
- **Internal API endpoint URLs** (e.g., `https://domain/api/internal-service/`)
- **SSH aliases or VM connection patterns** (e.g., `ssh myvm 'grep TOKEN ...'`)
- **Production health check URLs** with full domain+path
- **References to private companion repos** by name (e.g., `project-private/`)
- **Process-to-repo mappings** (reveals which GitHub repos power which services)

**Instead:** Use `"see privateContext/infrastructure.md"` as a pointer. Infrastructure details belong in privateContext, which is never public. For scripts that need these values at runtime, use environment variables with `:?` guards (fail loudly if unset) or source from privateContext files.

**Common violation patterns in deploy scripts:**
```bash
# BAD: Hardcoded paths and health check URLs
cd /opt/myservice
curl -sf https://mydomain.com/myservice/ > /dev/null

# GOOD: Externalized via env vars
DEPLOY_DIR="${DEPLOY_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$DEPLOY_DIR"
HEALTH_URL="${HEALTH_URL:-${APP_URL:-http://localhost:8080}/}"
curl -sf "$HEALTH_URL" > /dev/null
```

**Common violation patterns in context.md:**
```markdown
# BAD:
- Deploy: example.com/myapp via Apache ProxyPass to localhost:8080
- PM2 process: myapp (id 4)
- Port: 8080 (production), 5000 (dev)

# GOOD:
- Deploy details: see privateContext/infrastructure.md (myapp row)
```

## History Rewriting — Collateral Damage

`git filter-repo` replaces strings across **all commits including the current working tree**. This causes collateral damage when the replacement is too broad:

- A replacement for `/var/www/html` will also hit `.env.example` defaults, inline comments, and config fallbacks — even though the path itself isn't a secret (it's a standard Apache default).
- A replacement for a username in paths (e.g., `/home/someuser/`) will break any SSH fallback or token-fetch command that references that path, even in scripts that are otherwise fine.

**After any history rewrite:**
1. Diff the working tree against what you expect — `git diff HEAD` should be empty, but check for REDACTED_ artifacts in non-secret locations.
2. Run every script that changed. Syntax checks (`bash -n`) catch parse errors but not broken runtime behavior.
3. Check that gitignored files (`.env`, caches, state files) survived — `git reset --hard` and `git filter-repo` both wipe untracked/ignored files. Re-deploy them.
4. Verify on every machine the repo is cloned to (local + VM). A hard reset on the VM to match the rewritten remote will wipe gitignored `.env` files there too.

**Scope replacements narrowly.** Replace the full string (e.g., the complete webhook URL) rather than substrings that appear in innocent contexts (e.g., a username that's also part of standard paths).

## When a Secret is Accidentally Committed

1. **Rotate immediately** — the secret is compromised the moment it's pushed
2. **Rewrite history** — `git filter-repo` to remove from all commits
3. **Force-push** — update the remote
4. **Verify the rewrite** — `git log --all -p | grep <secret>` should return 0 matches
5. **Check for collateral** — grep for `REDACTED_` in the working tree; fix any unintended replacements
6. **Restore gitignored files** — `.env` files, caches, and state files are wiped by history rewrites and hard resets; re-deploy them to all machines
7. **Re-verify functionality** — run every affected script on every machine (local + VM); don't trust syntax checks alone
8. **Check GitHub cache** — PRs, issues, and cached pages may still show the secret
