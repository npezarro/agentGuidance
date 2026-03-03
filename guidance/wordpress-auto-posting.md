# WordPress Auto-Posting Setup

Claude Code sessions automatically post a private WordPress draft at the end of each interaction via the `Stop` hook. This works on any environment where Claude Code runs — CLI, VM, or cloud sandbox (claude.ai/code).

## How It Works

```
Claude Code session ends
  → Stop hook fires
  → Fetches post-to-wordpress.sh from agentGuidance repo
  → Reads last user prompt + assistant response from transcript
  → Redacts secrets (app passwords, API keys, tokens, IPs)
  → Posts as a private draft to YOUR_DOMAIN via WP REST API
```

The hook exits silently if credentials aren't found — nothing breaks.

## Architecture

| Component | Location |
|-----------|----------|
| Hook config | `.claude/settings.json` (per-repo, propagated by `scripts/propagate-hooks.sh`) |
| Posting script | `hooks/post-to-wordpress.sh` (fetched at runtime from agentGuidance) |
| Credentials | Environment variables or `.env` file (never committed) |

## Required Credentials

Two environment variables:

| Variable | Description |
|----------|-------------|
| `WP_USER` | WordPress username (e.g., `pezant`) |
| `WP_APP_PASSWORD` | WordPress application password (not the account password) |

### Credential Resolution Order

The script checks in this order and uses the first match:

1. Environment variables (set via `settings.local.json` `"env"` block or shell)
2. `$HOME/.env`
3. `$HOME/.env`

## Setup by Environment

### This VM (YOUR_VM) — Already Done

Credentials live in `$HOME/.env`:

```
WP_USER=YOUR_WP_USERNAME
WP_APP_PASSWORD=<application password>
```

The `.env` file is sourced automatically by the hook. No additional setup needed.

### Claude Code CLI (other machines)

Create `$HOME/.env` with the two variables:

```bash
echo 'WP_USER=YOUR_WP_USERNAME' >> ~/.env
echo 'WP_APP_PASSWORD=<your-app-password>' >> ~/.env
```

### Claude Code on the Web (claude.ai/code)

Cloud sandboxes don't have access to the VM's `.env`. Provide credentials via the project-level settings local file:

1. In the cloud sandbox, create `.claude/settings.local.json` in the repo root:

```json
{
  "env": {
    "WP_USER": "YOUR_WP_USERNAME",
    "WP_APP_PASSWORD": "<your-app-password>"
  }
}
```

2. This file is gitignored by default (Claude Code never commits `settings.local.json`). Credentials stay local to that sandbox session.

**Note:** You may need to recreate this file each time a new sandbox spins up, depending on sandbox persistence.

## Creating a WordPress Application Password

If you need a new application password (e.g., the current one is revoked or you need a separate one for cloud):

1. Log in to WordPress admin: `https://YOUR_DOMAIN/wp-admin/`
2. Go to **Users → Profile** (or the specific user's profile)
3. Scroll to **Application Passwords**
4. Enter a name (e.g., `claude-code-cloud`) and click **Add New Application Password**
5. Copy the generated password immediately — it's shown only once
6. The password format is: `xxxx xxxx xxxx xxxx xxxx xxxx` (six groups of four characters, spaces optional)

Alternatively, via WP-CLI on the VM:

```bash
wp user application-password create pezant claude-code-cloud --porcelain
```

This outputs only the password string.

## WordPress API Details

| Setting | Value |
|---------|-------|
| Site | `https://YOUR_DOMAIN` |
| API endpoint | `https://YOUR_DOMAIN/wp-json/wp/v2/posts` |
| Auth method | HTTP Basic Auth (base64-encoded `user:app_password`) |
| Post status | `private` (not visible to the public) |
| Timeout | 10 seconds |

## Post Format

Each post includes:

- **Title:** First ~60 characters of the user's prompt
- **Body:** The user's prompt (blockquoted), the assistant's response, session metadata (timestamp, session ID, working directory)
- **Redaction:** Secrets, tokens, API keys, private IPs, and credentials are pattern-matched and scrubbed before posting

## Propagation

The hook is propagated to all repos via:

```bash
cd ~/agentGuidance
bash scripts/propagate-hooks.sh --dry-run   # preview
bash scripts/propagate-hooks.sh             # push to all repos
```

This copies `.claude/settings.json` and `CLAUDE.md` to every repo under `npezarro/`. The settings include both the SessionStart hook (fetches global rules) and the Stop hook (auto-posting).

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Posts not appearing | Check that `WP_USER` and `WP_APP_PASSWORD` are set. Run `source ~/.env && echo $WP_USER` to verify. |
| 401 Unauthorized | Application password may be revoked. Create a new one in WP admin. |
| 403 Forbidden | The WP user may not have `publish_posts` capability. Verify the user role is Editor or Administrator. |
| Hook not firing | Check `.claude/settings.json` exists in the repo and contains the `Stop` hook. |
| Truncated posts | By design — prompts over 300 chars and responses over 2000 chars are truncated with a note. |
