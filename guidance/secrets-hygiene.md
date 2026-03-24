# Secrets Hygiene

Rules for handling secrets, credentials, and infrastructure details in code — especially in public repositories.

## The Core Rule

**Never commit secrets, infrastructure specifics, or internal paths to a repository that is (or could become) public.** This includes:
- API keys, tokens, webhook URLs
- IP addresses, hostnames, SSH aliases
- Internal directory paths (home directories, deploy paths)
- SSH commands that reveal server structure
- Architecture docs with specific IPs, ports, or usernames

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

## Pre-Commit Checklist

Before committing to any public repo, verify:

1. `grep -rn 'ssh.*@\|BEGIN.*KEY\|api.key\|webhook' .` — no secrets in staged files
2. No IP addresses in code (check: `grep -rn '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' .`)
3. No absolute paths to home directories
4. `.gitignore` covers `.env*` files
5. Config files use environment variables, not hardcoded values

## Architecture Documentation

When documenting internal systems in a public repo:
- Describe the **pattern** (e.g., "reverse SSH tunnel to local machine"), not the **specifics** (e.g., "ssh -p 2222 user@1.2.3.4")
- Use generic terms: "cloud VM", "local machine", "the bot" — not hostnames or IPs
- Keep incident details focused on the **lesson**, not the infrastructure layout
- If specifics are needed, put them in a private repo or local notes

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
