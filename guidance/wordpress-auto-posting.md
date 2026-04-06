# WordPress Auto-Posting Setup

Claude Code sessions automatically post a private WordPress draft at the end of each interaction via the `Stop` hook. This works on any environment where Claude Code runs — CLI, VM, or cloud sandbox (claude.ai/code).

## How It Works

```
Claude Code session ends
  → Stop hook fires
  → Fetches post-to-wordpress.sh from agentGuidance repo
  → Reads last user prompt + assistant response from transcript
  → Redacts secrets (app passwords, API keys, tokens, IPs)
  → Posts as a private draft to your WordPress site via WP REST API
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
| `WP_USER` | WordPress username |
| `WP_APP_PASSWORD` | WordPress application password (not the account password) |

### Credential Resolution Order

The script checks in this order and uses the first match:

1. Environment variables (set via `settings.local.json` `"env"` block or shell)
2. `$HOME/.env`

## Setup by Environment

### Your Server — Set `.env`

Create or update `$HOME/.env` with your WordPress credentials:

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

Cloud sandboxes don't have access to the server's `.env`. Provide credentials via the project-level settings local file:

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

1. Log in to your WordPress admin dashboard
2. Go to **Users → Profile** (or the specific user's profile)
3. Scroll to **Application Passwords**
4. Enter a name (e.g., `claude-code-cloud`) and click **Add New Application Password**
5. Copy the generated password immediately — it's shown only once
6. The password format is: `xxxx xxxx xxxx xxxx xxxx xxxx` (six groups of four characters, spaces optional)

Alternatively, via WP-CLI on your server:

```bash
wp user application-password create YOUR_WP_USERNAME claude-code-cloud --porcelain
```

This outputs only the password string.

## WordPress API Details

| Setting | Value |
|---------|-------|
| Site | Your WordPress site URL (set via `WP_SITE` env var or hardcoded in the hook) |
| API endpoint | `<your-site>/wp-json/wp/v2/posts` |
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

This copies `.claude/settings.json` and `CLAUDE.md` to every repo. The settings include both the SessionStart hook (fetches global rules) and the Stop hook (auto-posting).

## Manual / Agent-Initiated Posts

The auto-posting above is for session transcripts via the Stop hook. For **manual posts** (buying guides, deliverables, reports), post directly on the VM since the WP site is hosted there:

```bash
# Via WP-CLI (preferred — handles formatting, categories, tags)
ssh pezant-vm "wp post create --post_title='My Title' --post_content='<content>' --post_status=draft"

# Via local REST API on the VM
ssh pezant-vm "curl -s -X POST http://localhost/wp-json/wp/v2/posts \
  -u \$WP_USER:\$WP_APP_PASSWORD \
  -H 'Content-Type: application/json' \
  -d '{\"title\":\"My Title\",\"content\":\"<content>\",\"status\":\"draft\"}'"
```

**Why direct on VM:** The WP site runs on the VM itself, so direct access avoids remote auth complexity. Use WP-CLI for structured posts and the REST API for programmatic use.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Posts not appearing | Check that `WP_USER` and `WP_APP_PASSWORD` are set. Run `source ~/.env && echo $WP_USER` to verify. |
| 401 Unauthorized | Application password may be revoked. Create a new one in WP admin. |
| 403 Forbidden | The WP user may not have `publish_posts` capability. Verify the user role is Editor or Administrator. |
| Hook not firing | Check `.claude/settings.json` exists in the repo and contains the `Stop` hook. |
| Truncated posts | By design — prompts over 300 chars and responses over 2000 chars are truncated with a note. |
