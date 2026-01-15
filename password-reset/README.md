## Password Reset Portal (Express + SQLite)

Self-service password reset portal built as a safe, portfolio-ready demo:

- **Realistic reset flow**: request reset → “email” outbox → reset link → set new password
- **Security-minded behavior**: token hashing, expiry, one-time use, rate limiting, and user-enumeration resistance
- **Simple stack**: Node/Express + SQLite + static HTML UI

### Quick start

```bash
cd password-reset
npm install
npm start
```

Then open `http://localhost:3001` (note: **http**, not https).
If you’re also running other demos, this project defaults to port `3001` (set `PORT=3000` if you want).

### Demo user

On first run, the app seeds a demo user:

- Email: `demo.user@company.test`
- Password (initial): `ChangeMe123!ChangeMe123!`

### Seed your own email (so you can receive real messages)

By default, only `demo.user@company.test` exists. To request a reset for your real address, seed it:

```bash
SEED_USER_EMAIL="you@example.com" npm start
```

Optional:

- `SEED_USER_NAME`
- `SEED_USER_PASSWORD` (initial password; not required for the reset flow)

### Send real email via SMTP (optional)

The portal can send the reset email via SMTP **in addition to** the demo outbox.

You can configure SMTP either via environment variables **or directly in the UI** (homepage → “SMTP settings”).

Set these env vars before starting:

- `SMTP_ENABLED=true`
- `SMTP_HOST=...`
- `SMTP_PORT=587` (or `465`)
- `SMTP_SECURE=false` (true for port 465)
- `SMTP_USER=...` (optional if your SMTP server doesn’t require auth)
- `SMTP_PASS=...`
- `FROM_ADDRESS="Password Reset Demo <no-reply@yourdomain>"`

Example (combine with seeding your email):

```bash
SEED_USER_EMAIL="you@example.com" \
SMTP_ENABLED=true SMTP_HOST="smtp.gmail.com" SMTP_PORT=587 SMTP_SECURE=false \
SMTP_USER="your@gmail.com" SMTP_PASS="your_app_password" \
FROM_ADDRESS="Password Reset Demo <your@gmail.com>" \
npm start
```

If SMTP is enabled, success/failure is recorded in `GET /api/audit` under `smtpSent`.

### Demo flow (what to show an employer)

1) Open `http://localhost:3000` and request a reset for `demo.user@company.test`.
2) Open the “Demo Outbox” page (`/outbox.html`) and click the reset link.
3) Set a new password (policy: 14+ chars, upper/lower/number/symbol, not very common).
4) Refresh the outbox and request another reset to show:
   - tokens expire (30 min) and are **one-time use**
   - request endpoint returns the same message for unknown users (**no enumeration**)
   - request rate limiting (per-IP and per-identifier)
5) (Optional) Review recent audit events:
   - `GET /api/audit`

### API quick reference

- `POST /api/reset/request`
  - body: `{ "identifier": "email@example.com" }`
  - always returns success message (anti-enumeration)
  - in demo mode writes an “email” to the outbox
- `POST /api/reset/confirm`
  - body: `{ "token": "...", "newPassword": "..." }`
  - validates token hash + expiry + one-time use; sets new password hash
- `GET /api/outbox` (demo-only)
  - returns up to 25 most recent outbox messages
- `GET /api/audit`
  - returns up to 50 most recent audit events
- `GET /health`

### Security notes (what this demonstrates)

- **Reset tokens are not stored raw**: only a SHA-256 hash of the token is stored in SQLite.
- **Enumeration-resistant UX**: the request endpoint returns the same message regardless of whether a user exists.
- **Rate limiting**: request endpoint is limited per-IP and per-identifier.
- **Audit trail**: reset requests and confirmations are logged (without leaking secrets).

### Configuration

- `PORT` (default `3000`)
- `DEMO_MODE` (default `true`) — when true, enables the Outbox feature (`/outbox.html`, `GET /api/outbox`)
- `TRUST_PROXY` — set if you run behind a proxy and want correct IPs for rate limiting/auditing
