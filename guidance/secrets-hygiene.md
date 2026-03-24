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

## When a Secret is Accidentally Committed

1. **Rotate immediately** — the secret is compromised the moment it's pushed
2. **Rewrite history** — `git filter-repo` to remove from all commits
3. **Force-push** — update the remote
4. **Check GitHub cache** — PRs, issues, and cached pages may still show the secret
5. **Verify** — `git log --all -p | grep <secret>` should return 0 matches
