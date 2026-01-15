const crypto = require('crypto');
const express = require('express');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const nodemailer = require('nodemailer');
const path = require('path');

const bcrypt = require('bcryptjs');
const { all, get, run } = require('./db');

const app = express();
const PORT = process.env.PORT || 3001;
const DEMO_MODE = (process.env.DEMO_MODE || 'true').toLowerCase() !== 'false';
const DEMO_ALLOW_USER_PROVISIONING =
  (process.env.DEMO_ALLOW_USER_PROVISIONING || 'true').toLowerCase() !== 'false';

const runtimeConfig = {
  smtp: {
    enabled: (process.env.SMTP_ENABLED || '').toLowerCase() === 'true',
    host: String(process.env.SMTP_HOST || ''),
    port: Number(process.env.SMTP_PORT || 587),
    secure: (process.env.SMTP_SECURE || '').toLowerCase() === 'true',
    user: String(process.env.SMTP_USER || ''),
    pass: String(process.env.SMTP_PASS || ''),
    fromAddress: String(process.env.FROM_ADDRESS || 'no-reply@localhost'),
  },
};

let smtpTransport = null;
let smtpTransportKey = '';

function smtpKey(cfg) {
  return [
    cfg.enabled ? '1' : '0',
    cfg.host || '',
    String(cfg.port || ''),
    cfg.secure ? '1' : '0',
    cfg.user || '',
    cfg.pass || '',
    cfg.fromAddress || '',
  ].join('|');
}

function ensureSmtpTransport() {
  const cfg = runtimeConfig.smtp;
  if (!cfg.enabled || !cfg.host) return null;

  const key = smtpKey(cfg);
  if (smtpTransport && smtpTransportKey === key) return smtpTransport;

  const auth = cfg.user && cfg.pass ? { user: cfg.user, pass: cfg.pass } : undefined;
  smtpTransport = nodemailer.createTransport({
    host: cfg.host,
    port: cfg.port,
    secure: !!cfg.secure,
    auth,
  });
  smtpTransportKey = key;
  return smtpTransport;
}

// If you run behind a proxy (nginx, etc) set TRUST_PROXY=1.
if (process.env.TRUST_PROXY) {
  app.set('trust proxy', process.env.TRUST_PROXY);
}

// Helmet is great, but its default CSP blocks inline scripts.
// This demo UI intentionally uses small inline scripts for simplicity.
app.use(
  helmet({
    contentSecurityPolicy: false,
  }),
);
app.use(express.json({ limit: '16kb' }));
app.use(express.static(path.join(__dirname, 'public')));

function normalizeIdentifier(value) {
  return String(value || '')
    .trim()
    .toLowerCase();
}

function clientIp(req) {
  // express-rate-limit uses req.ip; we also capture ip for audits
  return req.ip || req.connection?.remoteAddress || '';
}

function isLocalRequest(req) {
  const ip = clientIp(req);
  return ip === '127.0.0.1' || ip === '::1' || ip === '::ffff:127.0.0.1';
}

function nowIso() {
  return new Date().toISOString();
}

function addMinutes(date, minutes) {
  return new Date(date.getTime() + minutes * 60_000);
}

function hashResetToken(token) {
  // Store only a hash in DB (defense-in-depth if DB is exposed).
  return crypto.createHash('sha256').update(token, 'utf8').digest('hex');
}

function timingSafeEqualHex(aHex, bHex) {
  try {
    const a = Buffer.from(String(aHex), 'hex');
    const b = Buffer.from(String(bHex), 'hex');
    if (a.length !== b.length) return false;
    return crypto.timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

function passwordPolicy(newPassword) {
  const pwd = String(newPassword || '');
  if (pwd.length < 14) return 'Password must be at least 14 characters.';
  if (!/[a-z]/.test(pwd)) return 'Password must include a lowercase letter.';
  if (!/[A-Z]/.test(pwd)) return 'Password must include an uppercase letter.';
  if (!/[0-9]/.test(pwd)) return 'Password must include a number.';
  if (!/[^A-Za-z0-9]/.test(pwd)) return 'Password must include a symbol.';

  const lowered = pwd.toLowerCase();
  const common = [
    'password',
    'password1',
    'password123',
    'qwerty',
    'letmein',
    'welcome',
    'admin',
    'iloveyou',
    '123456',
    '123456789',
    '12345678',
    '111111',
    'monkey',
    'dragon',
  ];
  if (common.some((c) => lowered.includes(c))) return 'Password is too common.';
  return null;
}

async function audit(type, { userId = null, ip = null, ua = null, details = null } = {}) {
  await run(
    `
    INSERT INTO audit_events (type, user_id, ip, ua, details_json, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
    `,
    [type, userId, ip, ua, details ? JSON.stringify(details) : null, nowIso()],
  );
}

async function maybeSendEmail({ to, subject, text }) {
  const transport = ensureSmtpTransport();
  if (!transport) return { sent: false, error: null };
  await transport.sendMail({
    from: runtimeConfig.smtp.fromAddress,
    to,
    subject,
    text,
  });
  return { sent: true, error: null };
}

const requestLimiterByIp = rateLimit({
  windowMs: 15 * 60_000,
  limit: 25,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
});

const requestLimiterByIdentifier = rateLimit({
  windowMs: 15 * 60_000,
  limit: 5,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: (req) => {
    const identifier = normalizeIdentifier(req.body?.identifier);
    return identifier ? `id:${identifier}` : `ip:${clientIp(req)}`;
  },
});

app.get('/api/config', (req, res) => {
  res.json({
    demoMode: DEMO_MODE,
    allowUserProvisioning: DEMO_MODE && DEMO_ALLOW_USER_PROVISIONING,
    smtp: {
      enabled: !!runtimeConfig.smtp.enabled,
      configured: !!(runtimeConfig.smtp.enabled && runtimeConfig.smtp.host),
      host: runtimeConfig.smtp.host || '',
      port: runtimeConfig.smtp.port || 587,
      secure: !!runtimeConfig.smtp.secure,
      user: runtimeConfig.smtp.user || '',
      fromAddress: runtimeConfig.smtp.fromAddress || '',
    },
  });
});

app.post('/api/config/smtp', async (req, res) => {
  if (!DEMO_MODE || !isLocalRequest(req)) {
    res.status(404).json({ error: 'Not found' });
    return;
  }

  const enabled = !!req.body?.enabled;
  const host = String(req.body?.host || '').trim();
  const port = Number(req.body?.port || 587);
  const secure = !!req.body?.secure;
  const user = String(req.body?.user || '').trim();
  const pass = String(req.body?.pass || '');
  const fromAddress = String(req.body?.fromAddress || '').trim();

  if (enabled) {
    if (!host) {
      res.status(400).json({ error: 'SMTP host is required when enabled.' });
      return;
    }
    if (!Number.isFinite(port) || port < 1 || port > 65535) {
      res.status(400).json({ error: 'SMTP port must be a number between 1 and 65535.' });
      return;
    }
    if (!fromAddress) {
      res.status(400).json({ error: 'From address is required when enabled.' });
      return;
    }
  }

  runtimeConfig.smtp.enabled = enabled;
  runtimeConfig.smtp.host = host;
  runtimeConfig.smtp.port = port;
  runtimeConfig.smtp.secure = secure;
  runtimeConfig.smtp.user = user;
  runtimeConfig.smtp.pass = pass;
  runtimeConfig.smtp.fromAddress = fromAddress || runtimeConfig.smtp.fromAddress;

  // Force transport rebuild on next send.
  smtpTransport = null;
  smtpTransportKey = '';

  let verified = false;
  let verifyError = null;
  try {
    const transport = ensureSmtpTransport();
    if (transport) {
      await transport.verify();
      verified = true;
    }
  } catch (err) {
    verifyError = err?.message || String(err);
  }

  await audit('config.smtp.updated', {
    ip: clientIp(req),
    ua: req.get('user-agent') || '',
    details: {
      enabled,
      host: host ? '[set]' : '',
      port,
      secure,
      user: user ? '[set]' : '',
      fromAddress: fromAddress ? '[set]' : '',
      verified,
      verifyError: verifyError ? String(verifyError).slice(0, 300) : null,
    },
  });

  res.json({
    ok: true,
    verified,
    verifyError,
  });
});

app.post('/api/reset/request', requestLimiterByIp, requestLimiterByIdentifier, async (req, res) => {
  const ip = clientIp(req);
  const ua = req.get('user-agent') || '';
  const identifier = normalizeIdentifier(req.body?.identifier);

  // Always return a generic response to avoid user enumeration.
  const genericOk = {
    ok: true,
    message: 'If an account exists, a password reset link has been sent.',
    outboxUrl: DEMO_MODE ? '/outbox.html' : undefined,
  };

  if (!identifier) {
    await audit('reset.request.rejected', { ip, ua, details: { reason: 'missing_identifier' } });
    res.json(genericOk);
    return;
  }

  try {
    let user = await get('SELECT * FROM users WHERE email = ? AND disabled = 0', [identifier]);

    if (!user) {
      if (DEMO_MODE && DEMO_ALLOW_USER_PROVISIONING) {
        const displayName = identifier.split('@')[0]?.slice(0, 60) || 'User';
        const randomPwd = crypto.randomBytes(24).toString('base64url');
        const pwdHash = await bcrypt.hash(randomPwd, 12);
        const now = nowIso();

        await run(
          `
          INSERT OR IGNORE INTO users (email, display_name, password_hash, disabled, created_at, updated_at)
          VALUES (?, ?, ?, 0, ?, ?)
          `,
          [identifier, displayName, pwdHash, now, now],
        );
        user = await get('SELECT * FROM users WHERE email = ? AND disabled = 0', [identifier]);
        await audit('reset.request.provisioned', { userId: user?.id || null, ip, ua, details: { identifier } });
      } else {
        await audit('reset.request.unknown', { ip, ua, details: { identifier } });
        res.json(genericOk);
        return;
      }
    }

    const token = crypto.randomBytes(32).toString('base64url');
    const tokenHash = hashResetToken(token);
    const expiresAt = addMinutes(new Date(), 30).toISOString();
    const createdAt = nowIso();

    await run(
      `
      INSERT INTO password_resets (user_id, token_hash, expires_at, used_at, request_ip, request_ua, created_at)
      VALUES (?, ?, ?, NULL, ?, ?, ?)
      `,
      [user.id, tokenHash, expiresAt, ip, ua, createdAt],
    );

    const baseUrl = `${req.protocol}://${req.get('host')}`;
    const resetLink = `${baseUrl}/reset.html?token=${encodeURIComponent(token)}`;
    const subject = 'Reset your password';
    const body = `Hi ${user.display_name},\n\nWe received a request to reset your password.\n\nReset link (demo): ${resetLink}\n\nThis link expires in 30 minutes.\nIf you did not request this, you can ignore this email.\n`;

    if (DEMO_MODE) {
      await run(
        `
        INSERT INTO outbox_emails (to_address, subject, body, created_at)
        VALUES (?, ?, ?, ?)
        `,
        [user.email, subject, body, createdAt],
      );
    }

    let emailResult = { sent: false, error: null };
    try {
      emailResult = await maybeSendEmail({ to: user.email, subject, text: body });
    } catch (err) {
      emailResult = { sent: false, error: err?.message || String(err) };
    }
    await audit('reset.request.created', {
      userId: user.id,
      ip,
      ua,
      details: {
        expiresAt,
        smtpSent: emailResult.sent || false,
        smtpError: emailResult.error ? String(emailResult.error).slice(0, 300) : null,
      },
    });
  } catch (err) {
    // Intentionally keep errors generic in the API response.
    await audit('reset.request.error', { ip, ua, details: { message: err.message } });
  }

  res.json(genericOk);
});

app.post('/api/reset/confirm', async (req, res) => {
  const ip = clientIp(req);
  const ua = req.get('user-agent') || '';

  const token = String(req.body?.token || '').trim();
  const newPassword = String(req.body?.newPassword || '');

  if (!token || !newPassword) {
    await audit('reset.confirm.rejected', { ip, ua, details: { reason: 'missing_token_or_password' } });
    res.status(400).json({ error: 'Token and newPassword are required.' });
    return;
  }

  const policyError = passwordPolicy(newPassword);
  if (policyError) {
    await audit('reset.confirm.rejected', { ip, ua, details: { reason: 'password_policy' } });
    res.status(400).json({ error: policyError });
    return;
  }

  const presentedHash = hashResetToken(token);

  try {
    // Fetch potential match and compare in code to avoid subtle timing leaks on malformed tokens.
    // Since token_hash is indexed, the query remains fast; we still do a timingSafeEqual check.
    const candidate = await get(
      `
      SELECT pr.*, u.email as user_email, u.display_name as user_display_name, u.disabled as user_disabled
      FROM password_resets pr
      JOIN users u ON u.id = pr.user_id
      WHERE pr.token_hash = ? AND pr.used_at IS NULL
      `,
      [presentedHash],
    );

    if (!candidate || candidate.user_disabled) {
      await audit('reset.confirm.invalid', {
        ip,
        ua,
        details: { tokenHashPrefix: presentedHash.slice(0, 8) },
      });
      res.status(400).json({ error: 'Invalid or expired reset token.' });
      return;
    }

    if (!timingSafeEqualHex(candidate.token_hash, presentedHash)) {
      await audit('reset.confirm.invalid', {
        ip,
        ua,
        details: { tokenHashPrefix: presentedHash.slice(0, 8), mismatch: true },
      });
      res.status(400).json({ error: 'Invalid or expired reset token.' });
      return;
    }

    const expiresAt = new Date(candidate.expires_at);
    if (Number.isNaN(expiresAt.valueOf()) || expiresAt <= new Date()) {
      await audit('reset.confirm.expired', { userId: candidate.user_id, ip, ua });
      res.status(400).json({ error: 'Invalid or expired reset token.' });
      return;
    }

    const newHash = await bcrypt.hash(newPassword, 12);
    const now = nowIso();

    await run('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?', [newHash, now, candidate.user_id]);
    await run('UPDATE password_resets SET used_at = ? WHERE id = ?', [now, candidate.id]);
    await audit('reset.confirm.success', { userId: candidate.user_id, ip, ua });

    res.json({ ok: true });
  } catch (err) {
    await audit('reset.confirm.error', { ip, ua, details: { message: err.message } });
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

app.get('/api/outbox', async (_req, res) => {
  if (!DEMO_MODE) {
    res.status(404).json({ error: 'Not found' });
    return;
  }
  const emails = await all(
    `
    SELECT id, to_address, subject, body, created_at
    FROM outbox_emails
    ORDER BY datetime(created_at) DESC
    LIMIT 25
    `,
  );
  res.json(emails);
});

app.get('/api/audit', async (_req, res) => {
  // Useful for demo; keep it minimal.
  const events = await all(
    `
    SELECT id, type, user_id, ip, ua, details_json, created_at
    FROM audit_events
    ORDER BY datetime(created_at) DESC
    LIMIT 50
    `,
  );
  res.json(events);
});

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

app.listen(PORT, () => {
  console.log(`Password reset portal listening on http://localhost:${PORT}`);
});

