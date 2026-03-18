#!/usr/bin/env node
/**
 * format-daily-log.js — Reads a daily-tldr JSON report and posts a
 * work-focused summary to #daily-logs via Discord webhook.
 *
 * Unlike format-report.js (health/ops focus), this formatter emphasizes
 * what work was completed — no vulnerability data, no build status,
 * no action items. Purely informational.
 *
 * Usage: node format-daily-log.js <report.json>
 * Requires: DISCORD_DAILY_LOGS_WEBHOOK_URL env var
 */

const fs = require('fs');
const path = require('path');

// Load .env from script directory
const envPath = path.join(__dirname, '.env');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq > 0) {
      process.env[trimmed.slice(0, eq)] = trimmed.slice(eq + 1);
    }
  }
}

const WEBHOOK_URL = process.env.DISCORD_DAILY_LOGS_WEBHOOK_URL;
if (!WEBHOOK_URL) {
  console.error('DISCORD_DAILY_LOGS_WEBHOOK_URL not set');
  process.exit(1);
}

const reportPath = process.argv[2];
if (!reportPath || !fs.existsSync(reportPath)) {
  console.error('Usage: node format-daily-log.js <report.json>');
  process.exit(1);
}

const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));

/**
 * Summarize commits for a repo into a prose-style description.
 * Groups by author and uses subject lines (no SHAs).
 */
function summarizeCommits(repo) {
  if (!repo.commits || repo.commit_count === 0) return null;

  let commits;
  if (Array.isArray(repo.commits)) {
    commits = repo.commits;
  } else {
    // Legacy flat string format: "hash subject (author)"
    commits = repo.commits.split('\n').filter(Boolean).map(line => {
      const match = line.match(/^([a-f0-9]+)\s+(.+)\s+\((.+)\)$/);
      if (match) {
        return { hash: match[1], subject: match[2], author: match[3] };
      }
      return { hash: '', subject: line, author: 'unknown' };
    });
  }

  // Group by author
  const byAuthor = {};
  for (const c of commits) {
    const author = c.author || 'unknown';
    if (!byAuthor[author]) byAuthor[author] = [];
    byAuthor[author].push(c.subject);
  }

  const lines = [];
  for (const [author, subjects] of Object.entries(byAuthor)) {
    const displayed = subjects.slice(0, 5);
    const summary = displayed.map(s => `- ${s}`).join('\n');
    if (Object.keys(byAuthor).length > 1) {
      lines.push(`**${author}** (${subjects.length}):\n${summary}`);
    } else {
      lines.push(summary);
    }
    if (subjects.length > 5) {
      lines.push(`- ...and ${subjects.length - 5} more`);
    }
  }

  return lines.join('\n');
}

function buildEmbed(report) {
  const { date, active_repos, repos } = report;

  const active = repos.filter(r => r.commit_count > 0);
  const totalCommits = active.reduce((sum, r) => sum + r.commit_count, 0);

  // No activity — suppress post
  if (totalCommits === 0) return null;

  // Sort by commit count descending
  active.sort((a, b) => b.commit_count - a.commit_count);

  // Build per-repo fields
  const repoSections = active.map(r => {
    const summary = summarizeCommits(r);
    return {
      name: `${r.name} — ${r.commit_count} commit${r.commit_count !== 1 ? 's' : ''}`,
      value: summary ? summary.slice(0, 1024) : '_No commit details available._',
      inline: false,
    };
  });

  // Discord embeds have a 25-field limit; truncate if needed
  const fields = repoSections.slice(0, 20);

  return {
    embeds: [{
      title: `Daily Log — ${date}`,
      description: `**${totalCommits} commit${totalCommits !== 1 ? 's' : ''}** across **${active_repos} repo${active_repos !== 1 ? 's' : ''}** in the last 24 hours.\n\nSummary of work completed. For operational health, see #tldr.`,
      color: 0x5865F2, // Discord blurple — neutral, informational
      fields,
      footer: { text: 'daily-log • agentGuidance' },
      timestamp: new Date().toISOString(),
    }],
    username: 'Daily Log',
  };
}

async function post(payload, attempt = 1) {
  const MAX_ATTEMPTS = 3;
  try {
    const res = await fetch(WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (res.status === 429) {
      // Rate limited — respect retry_after
      const body = await res.json().catch(() => ({}));
      const retryAfter = (body.retry_after || 5) * 1000;
      if (attempt < MAX_ATTEMPTS) {
        console.log(`Rate limited, retrying in ${retryAfter}ms (attempt ${attempt}/${MAX_ATTEMPTS})`);
        await new Promise(r => setTimeout(r, retryAfter));
        return post(payload, attempt + 1);
      }
    }

    if (!res.ok) {
      const text = await res.text();
      if (attempt < MAX_ATTEMPTS) {
        const delay = Math.pow(2, attempt) * 1000;
        console.log(`Webhook failed (${res.status}), retrying in ${delay}ms (attempt ${attempt}/${MAX_ATTEMPTS})`);
        await new Promise(r => setTimeout(r, delay));
        return post(payload, attempt + 1);
      }
      throw new Error(`Webhook failed after ${MAX_ATTEMPTS} attempts: ${res.status} — ${text}`);
    }
  } catch (err) {
    if (err.message?.includes('Webhook failed after')) throw err;
    if (attempt < MAX_ATTEMPTS) {
      const delay = Math.pow(2, attempt) * 1000;
      console.log(`Network error, retrying in ${delay}ms (attempt ${attempt}/${MAX_ATTEMPTS})`);
      await new Promise(r => setTimeout(r, delay));
      return post(payload, attempt + 1);
    }
    throw err;
  }
}

(async () => {
  try {
    const embed = buildEmbed(report);
    if (!embed) {
      console.log('No activity today — skipping daily log post.');
      process.exit(0);
    }
    await post(embed);
    console.log('Daily log posted to #daily-logs.');
  } catch (err) {
    console.error('Failed to post daily log:', err.message);
    process.exit(1);
  }
})();
