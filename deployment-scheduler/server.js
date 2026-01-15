const express = require('express');
const path = require('path');
const { all, run, get } = require('./db');
const { startScheduler, triggerNow } = require('./scheduler');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.get('/api/services', async (_req, res) => {
  const services = await all('SELECT * FROM services ORDER BY name ASC');
  res.json(services);
});

app.get('/api/environments', async (_req, res) => {
  const environments = await all('SELECT * FROM environments ORDER BY name ASC');
  res.json(environments);
});

app.get('/api/schedules', async (_req, res) => {
  const schedules = await all(
    `
    SELECT s.*, sv.name as service_name, e.name as environment_name
    FROM schedules s
    JOIN services sv ON sv.id = s.service_id
    JOIN environments e ON e.id = s.environment_id
    ORDER BY datetime(s.scheduled_for) DESC
    `,
  );
  res.json(schedules);
});

app.post('/api/schedules', async (req, res) => {
  const { serviceId, environmentId, scheduledFor, note } = req.body || {};
  if (!serviceId || !environmentId || !scheduledFor) {
    res.status(400).json({ error: 'serviceId, environmentId, and scheduledFor are required' });
    return;
  }

  const parsedDate = new Date(scheduledFor);
  if (Number.isNaN(parsedDate.valueOf())) {
    res.status(400).json({ error: 'scheduledFor must be a valid date' });
    return;
  }

  const now = new Date().toISOString();
  await run(
    `
    INSERT INTO schedules (service_id, environment_id, scheduled_for, note, status, created_at, updated_at)
    VALUES (?, ?, ?, ?, 'pending', ?, ?)
    `,
    [serviceId, environmentId, parsedDate.toISOString(), note || '', now, now],
  );

  res.status(201).json({ ok: true });
});

app.post('/api/schedules/:id/cancel', async (req, res) => {
  const schedule = await get('SELECT * FROM schedules WHERE id = ?', [req.params.id]);
  if (!schedule) {
    res.status(404).json({ error: 'Schedule not found' });
    return;
  }
  if (schedule.status !== 'pending') {
    res.status(400).json({ error: 'Only pending schedules can be cancelled' });
    return;
  }
  const now = new Date().toISOString();
  await run('UPDATE schedules SET status = ?, updated_at = ? WHERE id = ?', ['cancelled', now, req.params.id]);
  res.json({ ok: true });
});

app.post('/api/schedules/:id/run', async (req, res) => {
  const result = await triggerNow(req.params.id);
  if (!result.ok) {
    res.status(400).json({ error: result.message });
    return;
  }
  res.json({ ok: true });
});

app.get('/api/logs', async (_req, res) => {
  const logs = await all(
    `
    SELECT l.*, s.service_id, s.environment_id, sv.name as service_name, e.name as environment_name
    FROM run_logs l
    JOIN schedules s ON s.id = l.schedule_id
    JOIN services sv ON sv.id = s.service_id
    JOIN environments e ON e.id = s.environment_id
    ORDER BY datetime(l.executed_at) DESC
    `,
  );
  res.json(logs);
});

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

app.listen(PORT, () => {
  console.log(`Deployment scheduler listening on http://localhost:${PORT}`);
  startScheduler();
});
