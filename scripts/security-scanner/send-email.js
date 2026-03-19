#!/usr/bin/env node
/**
 * send-email.js — Send security scan alert emails via SMTP.
 *
 * Reuses the same Gmail SMTP credentials as runeval.
 * Recipient is hardcoded to prevent misuse.
 *
 * Usage: node send-email.js <subject> <body-file>
 *   or:  echo "body" | node send-email.js <subject>
 *
 * Requires SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS env vars.
 * Reads from .env file if present.
 */

const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');

// ── Hardcoded allowed recipient ─────────────────────────────────────
const ALLOWED_RECIPIENT = 'ALERT_EMAIL_REDACTED';

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

// ── Main ────────────────────────────────────────────────────────────
async function main() {
  const subject = process.argv[2];
  if (!subject) {
    console.error('Usage: node send-email.js <subject> [body-file]');
    process.exit(1);
  }

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
      from: `"Security Scanner" <${from}>`,
      to: ALLOWED_RECIPIENT,
      subject,
      text: body,
      html: [
        '<div style="font-family: sans-serif; max-width: 600px; margin: 0 auto;">',
        `<h2 style="color: #e85d2f;">🔒 ${escapeHtml(subject)}</h2>`,
        '<div style="background: #fdf6f0; border-left: 4px solid #e85d2f; border-radius: 8px; padding: 20px; margin: 16px 0;">',
        htmlBody,
        '</div>',
        '<p style="color: #999; font-size: 12px;">— Security Scanner (agentGuidance/scripts/security-scanner)</p>',
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
