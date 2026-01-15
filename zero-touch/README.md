# Zero Touch Provisioning (ZTP)

Zero Touch Provisioning (ZTP) is a comprehensive, self-hosted automation system for securely onboarding, managing, and orchestrating devices in diverse IT environments. ZTP streamlines the provisioning and management workflow by automating every step—from initial enrollment to configuration updates—for Linux, macOS, and Windows devices.

## Features

- **API-Driven Enrollment**: Devices enroll themselves using secure, short-lived tokens, minimizing manual intervention and potential for error.


## Quickstart Demo

Below are steps to try out Zero Touch Provisioning in a development environment.

### 1. Start the Backend API

```bash
cd zero-touch/backend
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

This will launch the API at [http://localhost:8000](http://localhost:8000).

### 2. Create an Enrollment Token

Use `curl` to create a token (e.g., valid for 15 minutes):

```bash
curl -X POST "http://localhost:8000/enrollment/token" \
     -H "Content-Type: application/json" \
     -d '{"ttl_minutes": 15, "max_uses": 1}'
```

The response will include a token and an `enrollment_url`.

### 3. Onboard a Device

#### Linux/macOS

Use the provided shell script:

```bash
cd zero-touch/agent
TOKEN=<YOUR_TOKEN> ./bootstrap.sh
```

#### Windows

Use PowerShell:

```powershell
cd zero-touch/agent
.\bootstrap.ps1 -Token "<YOUR_TOKEN>"
```

The device will register with the API and appear in the inventory.

---

## Technical Architecture

- **API**: FastAPI backend (`zero-touch/backend/app/`).  
- **Database**: SQLite (default), using SQLModel.
- **Agent Scripts**: Platform-specific enrollment scripts in `zero-touch/agent/`.
- **Task Queue**: Celery for asynchronous provisioning runs.

## Key API Endpoints

- `POST /enrollment/token` — Create an enrollment token
- `POST /enrollment/register` — Register a device using a token
- `GET /devices/` — List registered devices
- `POST /workflows/{id}/run` — Trigger a provisioning workflow

See [backend/app/schemas.py](backend/app/schemas.py) for request/response models.

---

## Tips

- Set `API_BASE` environment variable to point agents to your backend API.
- Enrollment tokens are short-lived by design; re-issue as needed.
- Customize provisioning flows and blueprints under the `blueprints` API.

For further details, consult the source code or reach out via issues.



