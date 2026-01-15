const { all, run, get } = require('./db');

async function fetchDueSchedules() {
  return all(
    `
    SELECT s.*, sv.name as service_name, e.name as environment_name
    FROM schedules s
    JOIN services sv ON sv.id = s.service_id
    JOIN environments e ON e.id = s.environment_id
    WHERE s.status = 'pending' AND datetime(s.scheduled_for) <= datetime('now')
    ORDER BY s.scheduled_for ASC
    `,
  );
}

async function executeSchedule(schedule, source = 'auto') {
  const now = new Date().toISOString();
  await run('UPDATE schedules SET status = ?, updated_at = ? WHERE id = ?', ['executed', now, schedule.id]);
  await run(
    `INSERT INTO run_logs (schedule_id, executed_at, status, message)
     VALUES (?, ?, ?, ?)`,
    [
      schedule.id,
      now,
      'success',
      `${source} mock deploy of ${schedule.service_name} to ${schedule.environment_name}`,
    ],
  );
}

async function pollAndExecute() {
  const due = await fetchDueSchedules();
  for (const schedule of due) {
    await executeSchedule(schedule, 'auto');
  }
}

function startScheduler(intervalMs = 5000) {
  setInterval(() => {
    pollAndExecute().catch((err) => {
      // Keeping the console log small to avoid noisy output in the demo.
      console.error('Scheduler error', err.message);
    });
  }, intervalMs);
}

async function triggerNow(scheduleId) {
  const schedule = await get(
    `
    SELECT s.*, sv.name as service_name, e.name as environment_name
    FROM schedules s
    JOIN services sv ON sv.id = s.service_id
    JOIN environments e ON e.id = s.environment_id
    WHERE s.id = ?
    `,
    [scheduleId],
  );

  if (!schedule) {
    return { ok: false, message: 'Schedule not found' };
  }
  if (schedule.status !== 'pending') {
    return { ok: false, message: `Cannot run schedule with status ${schedule.status}` };
  }

  await executeSchedule(schedule, 'manual');
  return { ok: true };
}

module.exports = {
  startScheduler,
  triggerNow,
};
