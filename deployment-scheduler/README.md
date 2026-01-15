## Deployment Scheduler (Express + SQLite)

Simple demo that schedules mock deployments, runs them automatically or manually, and logs executions. Built to showcase API + UI + lightweight scheduling.

### Getting started
1) Install dependencies:
```
cd deployment-scheduler
npm install
```
2) Start the server (defaults to `http://localhost:3000`):
```
npm start
```
The app seeds example services and environments on first run. Data is stored in `data.sqlite`.

### What it does
- Create deployment schedules for a service + environment + time.
- In-process poller marks due schedules as executed and writes run logs (mock only).
- Manually trigger or cancel pending schedules.
- Minimal web UI to manage schedules and view logs.
- REST API for automation.

### API quick reference
- `GET /api/services` and `GET /api/environments` — seed data lists.
- `GET /api/schedules` — schedules with service/environment names.
- `POST /api/schedules` — body: `{ serviceId, environmentId, scheduledFor, note? }`.
- `POST /api/schedules/:id/run` — manual trigger (mock execution).
- `POST /api/schedules/:id/cancel` — cancel a pending schedule.
- `GET /api/logs` — execution history.
- `GET /health` — health check.

### Demo flow
1) Open `http://localhost:3000`.
2) Pick a service, environment, and time; click “Create Schedule”.
3) Watch pending items flip to executed when the time is reached (or click “Run now”).
4) Review log entries showing mock deploys per service/environment.