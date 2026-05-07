# WordPress Auto-Posting Setup

Claude Code sessions automatically save a markdown file at the end of each interaction via the `Stop` hook. Files are committed to `~/repos/wordpressPosts` for manual review before publishing to WordPress.

## How It Works

```
Claude Code session ends
  -> Stop hook fires
  -> Fetches post-to-wordpress.sh from agentGuidance repo
  -> Reads last user prompt + assistant response from transcript
  -> Redacts secrets (app passwords, API keys, tokens, IPs)
  -> Writes a .md file with YAML frontmatter to ~/repos/wordpressPosts/
  -> Commits and pushes to GitHub
```

The hook exits silently if the repo doesn't exist or jq isn't installed.

## Architecture

| Component | Location |
|-----------|----------|
| Hook config | `.claude/settings.json` (per-repo, propagated by `scripts/propagate-hooks.sh`) |
| Posting script | `hooks/post-to-wordpress.sh` (fetched at runtime from agentGuidance) |
| Output repo | `~/repos/wordpressPosts` (private GitHub repo) |

## File Format

Each .md file includes YAML frontmatter:

```yaml
---
title: "Session Closeout: Feature X"
date: 2026-05-06 15:43:46
session_id: abc123
project: my-repo
cwd: /home/user/repos/my-repo
---
```

Followed by the full assistant response (redacted).

## Title Extraction

Priority: first markdown heading > first sentence (10+ chars) > project name + date fallback.

## Deduplication

- Session-based: same `session_id` won't produce a second file
- Content-based: identical content (sha256 hash) won't produce a duplicate
- Cache dir: `~/.cache/wp-posts/` (auto-cleaned after 7 days)

## Redaction

Patterns scrubbed before writing:
- WordPress app passwords, GitHub tokens/PATs
- OpenAI/generic API keys, Bearer tokens
- Basic Auth headers, environment variable values (PASSWORD, SECRET, TOKEN, etc.)
- Credential URLs, private keys, private IPs (10.x, 192.168.x, 172.16-31.x)

## Publishing to WordPress

Do NOT post directly to WordPress via WP-CLI or the REST API. The file-based workflow (write .md to `~/repos/wordpressPosts/`, commit, push) is the current standard. Posts are reviewed and published separately. For deep closeouts and manual session reports, write the .md file to `~/repos/wordpressPosts/` with the same YAML frontmatter format.

## Propagation

The hook config is propagated to all repos via:

```bash
cd ~/repos/agentGuidance
bash scripts/propagate-hooks.sh
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Files not appearing | Check that `~/repos/wordpressPosts` exists and is a git repo |
| Hook not firing | Check `.claude/settings.json` exists in the repo and contains the `Stop` hook |
| Push failing | Check git remote and SSH key setup for wordpressPosts repo |
