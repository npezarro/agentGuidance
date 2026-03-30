#!/usr/bin/env node
/**
 * DEPRECATED — Use ~/repos/email-sender/send-email.sh instead.
 *
 * This file is kept for reference only. The security scanner's run.sh
 * has been updated to use the email-sender repo directly.
 *
 * Migration: ~/repos/email-sender/send-email.sh "Subject" --body-file file.txt --sender-name "Security Scanner"
 *
 * Original: send-email.js — Send security scan alert emails via SMTP.
 */
console.error('DEPRECATED: Use ~/repos/email-sender/send-email.sh instead');
process.exit(1);

const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');

// ── Load .env ───────────────────────────────────────────────────────
function loadEnv(envPath) {
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let val = trimmed.slice(eq + 1).trim();
    // Strip surrounding quotes
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = val;
  }
}

// Load local .env, then runeval's .env on the VM for SMTP creds
loadEnv(path.join(__dirname, '.env'));
loadEnv('/var/www/runeval/.env');

// ── Allowed recipient (loaded from .env above) ─────────────────────
const ALLOWED_RECIPIENT = process.env.ALERT_EMAIL;
if (!ALLOWED_RECIPIENT) {
  console.error('ALERT_EMAIL env var is required (set in .env or environment)');
  process.exit(1);
}

// ── Main ────────────────────────────────────────────────────────────
async function main() {
  const subject = process.argv[2];
  if (!subject) {
    console.error('Usage: node send-email.js <subject> [body-file]');
    process.exit(1);
  }

  const senderName = process.argv[4] || process.env.SENDER_NAME || 'Security Scanner';

  // Read body from file arg or stdin
  let body;
  const bodyFile = process.argv[3];
  if (bodyFile) {
    if (!fs.existsSync(bodyFile)) {
      console.error(`File not found: ${bodyFile}`);
      process.exit(1);
    }
    body = fs.readFileSync(bodyFile, 'utf8');
  } else {
    // Read from stdin
    body = fs.readFileSync(0, 'utf8');
  }

  const host = process.env.SMTP_HOST;
  const port = parseInt(process.env.SMTP_PORT || '587', 10);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;
  const from = process.env.SMTP_FROM || user || 'noreply@pezant.ca';

  if (!host || !user || !pass) {
    console.error('SMTP not configured (need SMTP_HOST, SMTP_USER, SMTP_PASS)');
    process.exit(1);
  }

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
  });

  try {
    await transporter.verify();
  } catch (err) {
    console.error(`SMTP verification failed: ${err.message}`);
    process.exit(1);
  }

  // Convert plain text body to basic HTML
  const htmlBody = escapeHtml(body)
    .replace(/^### (.+)$/gm, '<h4>$1</h4>')
    .replace(/^## (.+)$/gm, '<h3>$1</h3>')
    .replace(/^# (.+)$/gm, '<h2>$1</h2>')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/^- (.+)$/gm, '<li>$1</li>')
    .replace(/\n/g, '<br>');

  try {
    await transporter.sendMail({
      from: `"${senderName}" <${from}>`,
      to: ALLOWED_RECIPIENT,
      subject,
      text: body,
      html: [
        '<div style="font-family: sans-serif; max-width: 600px; margin: 0 auto;">',
        `<h2 style="color: #e85d2f;">${escapeHtml(subject)}</h2>`,
        '<div style="background: #fdf6f0; border-left: 4px solid #e85d2f; border-radius: 8px; padding: 20px; margin: 16px 0;">',
        htmlBody,
        '</div>',
        `<p style="color: #999; font-size: 12px;">— ${escapeHtml(senderName)}</p>`,
        '</div>',
      ].join('\n'),
    });

    console.log(`Email sent to ${ALLOWED_RECIPIENT}: ${subject}`);
  } catch (err) {
    console.error(`Failed to send email: ${err.message}`);
    process.exit(1);
  }
}

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

main();
