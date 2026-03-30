#!/usr/bin/env node
/**
 * format-report.js — Reads a daily-tldr JSON report and posts a
 * formatted Discord embed via webhook.
 *
 * Usage: node format-report.js <report.json>
 * Requires: DISCORD_WEBHOOK_URL env var
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

const WEBHOOK_URL = process.env.DISCORD_WEBHOOK_URL;
if (!WEBHOOK_URL) {
  console.error('DISCORD_WEBHOOK_URL not set');
  process.exit(1);
}

const reportPath = process.argv[2];
if (!reportPath || !fs.existsSync(reportPath)) {
  console.error('Usage: node format-report.js <report.json>');
  process.exit(1);
}

const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));

function buildEmbed(report) {
  const { date, total_repos, active_repos, issues_found, repos } = report;

  // Status emoji
  const statusEmoji = issues_found > 0 ? '⚠️' : '✅';

  // Build per-repo lines
  const repoLines = repos.map(r => {
    const parts = [];

    // Activity indicator
    if (r.commit_count > 0) {
      parts.push(`📝 ${r.commit_count} commit${r.commit_count !== 1 ? 's' : ''}`);
    } else {
      parts.push('💤 no activity');
    }

    // Vulnerability info
    if (r.vuln_total !== undefined) {
      if (r.vuln_high > 0) {
        parts.push(`🔴 ${r.vuln_high} high/crit vuln${r.vuln_high !== 1 ? 's' : ''}`);
      } else if (r.vuln_total > 0) {
        parts.push(`🟡 ${r.vuln_total} vuln${r.vuln_total !== 1 ? 's' : ''}`);
      } else {
        parts.push('🟢 clean');
      }
    }

    // Outdated deps
    if (r.outdated_count > 0) {
      parts.push(`📦 ${r.outdated_count} outdated`);
    }

    // Build status
    if (r.build_ok !== undefined) {
      parts.push(r.build_ok ? '🏗️ build ok' : '❌ build fail');
    }

    // Auto-fix applied
    if (r.auto_fix_applied) {
      parts.push('🔧 fix PR created');
    }

    return `**${r.name}** (${r.branch})\n${parts.join(' · ')}`;
  });

  // Split into active and quiet repos
  const active = repos.filter(r => r.commit_count > 0);
  const quiet = repos.filter(r => r.commit_count === 0);

  // Recent commits summary (top 5 most active)
  const commitSummary = active
    .sort((a, b) => b.commit_count - a.commit_count)
    .slice(0, 5)
    .map(r => {
      let lines;
      if (Array.isArray(r.commits)) {
        lines = r.commits.slice(0, 3).map(c => `${c.hash} ${c.subject} (${c.author})`);
      } else {
        lines = (r.commits || '').split('\n').filter(Boolean).slice(0, 3);
      }
      return `**${r.name}** (${r.commit_count})\n${lines.map(l => `\`${l}\``).join('\n')}`;
    })
    .join('\n\n');

  // Issues section
  const issueRepos = repos.filter(r =>
    (r.vuln_high > 0) || (r.build_ok === false)
  );
  const issueLines = issueRepos.map(r => {
    const problems = [];
    if (r.vuln_high > 0) problems.push(`${r.vuln_high} high/critical vulnerabilities`);
    if (r.build_ok === false) problems.push('build failing');
    return `**${r.name}**: ${problems.join(', ')}`;
  });

  const fields = [
    {
      name: '📊 Overview',
      value: `${total_repos} repos tracked · ${active_repos} active · ${issues_found} issue${issues_found !== 1 ? 's' : ''}`,
      inline: false,
    },
  ];

  if (commitSummary) {
    fields.push({
      name: '📝 Recent Activity',
      value: commitSummary.slice(0, 1024),
      inline: false,
    });
  }

  if (issueLines.length > 0) {
    fields.push({
      name: '⚠️ Needs Attention',
      value: issueLines.join('\n'),
      inline: false,
    });
  }

  if (quiet.length > 0) {
    fields.push({
      name: '💤 Quiet Repos',
      value: quiet.map(r => r.name).join(', '),
      inline: false,
    });
  }

  // Autonomous dev runs (last 24h)
  const autodev = report.autonomous_dev || [];
  if (autodev.length > 0) {
    const totalCost = autodev.reduce((sum, r) => {
      const c = parseFloat((r.cost || '$0').replace('$', ''));
      return sum + (isNaN(c) ? 0 : c);
    }, 0);
    const reposHit = [...new Set(autodev.map(r => r.repo).filter(Boolean))];
    const prs = autodev.filter(r => r.pr).length;
    const features = autodev.filter(r => r.feature_run).length;
    const standard = autodev.length - features;

    let summary = `${autodev.length} runs across ${reposHit.length} repo${reposHit.length !== 1 ? 's' : ''}`;
    summary += ` · ${prs} PR${prs !== 1 ? 's' : ''} created`;
    if (features > 0) summary += ` · ${features} feature, ${standard} standard`;
    summary += ` · $${totalCost.toFixed(2)} total`;
    summary += `\n${reposHit.join(', ')}`;

    fields.push({
      name: '🤖 Autonomous Dev',
      value: summary.slice(0, 1024),
      inline: false,
    });
  }

  // Color: green if no issues, yellow if issues
  const color = issues_found > 0 ? 0xf59e0b : 0x22c55e;

  return {
    embeds: [{
      title: `${statusEmoji} Daily TLDR — ${date}`,
      description: `Automated health check across ${total_repos} repositories.`,
      color,
      fields,
      footer: { text: 'daily-tldr • agentGuidance' },
      timestamp: new Date().toISOString(),
    }],
    username: 'Daily TLDR',
  };
}

async function post(payload) {
  const res = await fetch(WEBHOOK_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Webhook failed: ${res.status} — ${text}`);
  }
}

(async () => {
  try {
    const embed = buildEmbed(report);
    await post(embed);
    console.log('Discord TLDR posted successfully.');
  } catch (err) {
    console.error('Failed to post:', err.message);
    process.exit(1);
  }
})();
