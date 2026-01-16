# workplace-automation
This repository, **workplace-automation**, is a collection of small projects demonstrating different aspects and patterns of automation in various environments. Each project is a self-contained example showcasing how automation can streamline workflows, deploy infrastructure, or manage applications effectively.

## Projects

### Zero Touch Provisioning

**Zero Touch Provisioning (ZTP)** is a comprehensive self-hosted system designed to automate the onboarding, management, and orchestration of devices within a diverse IT environment. With ZTP, you can securely enroll new devices—regardless of OS or hardware—configure them on first boot, and push application or configuration updates with minimal manual effort.

Key features:
- **API-Driven Enrollment**: Devices register themselves using short-lived enrollment tokens, minimizing manual steps and reducing risk.
- **Secure API**: All sensitive operations are protected with an API Key, and Traefik is used as the modern reverse proxy to route requests to internal services.
- **Blueprints & Workflows**: Define blueprints to describe desired configurations or application states, and apply them to devices via a workflow engine.
- **Agent Bootstrap for All Platforms**: Simple bootstrap scripts are provided for Linux/macOS (shell script) and Windows (PowerShell), making agent installation seamless for new hosts.
- **Modern Stack**: Built using Docker Compose, with services for API (Python/FastAPI), PostgreSQL (data store), Redis (optional for queueing), Traefik (reverse proxy), and a static UI.
- **Extensible Architecture**: The system is designed to be easily extended, e.g., integrating Single Sign-On or adding new device operations.

The ZTP mini-project demonstrates how zero-touch and infrastructure-as-code principles can be applied to automating onboarding and operations for a mixed fleet of devices, such as servers, workstations, or even IoT endpoints.

To try it out locally:

1. Clone the repo and run `docker compose up` in the `zero-touch` directory.
2. Review the API endpoints, bootstrap scripts, and process for enrolling a device as described in the included documentation and UI.

See the `zero-touch/README.md` and `zero-touch/ui/index.html` for a complete demonstration and further technical documentation.


### Deployment Scheduler

**Deployment Scheduler** is a lightweight demo service for managing and automating mock deployments across various services and environments. It showcases automation patterns with a REST API layer and web UI, using a simple in-process scheduling and logging system built with Node.js, Express, and SQLite.

Key features:
- **Easy Scheduling**: Create deployment schedules for a specific service and environment, either as one-time or recurring entries.
- **Automated & Manual Execution**: A scheduler runs in the background to execute due deployments, while users can also trigger or cancel them manually via the UI.
- **API & UI**: A minimal web interface for managing schedules and logs, plus a set of REST endpoints for scripting and integration.
- **Run Logs**: Every deployment run (automatic or manual) is logged for review and audit.
- **Demo Data on First Run**: Services, environments, and example schedules are seeded automatically.

To try it out locally:

1. Change into `deployment-scheduler`, then install and start:
   ```bash
   cd deployment-scheduler
   npm install
   npm start
   ```
2. Visit `http://localhost:3000` in your browser to manage or schedule deployments.

See the `deployment-scheduler/README.md` for API references, example flows, and technical documentation.

---

### Password Reset Portal

**Password Reset Portal** is a safe, realistic self-service password reset demo, designed to demonstrate secure automation and workflow handling surrounding user password recovery. The stack is Node/Express and SQLite, with a demo UI.

Key features:
- **End-to-End Reset Flow**: Request a reset, receive a link via a mock (or real) email, and securely set a new password.
- **Security Best Practices**: Includes token hashing, expiry, one-time use, rate limiting, and user enumeration resistance.
- **Demo Outbox & Real Email Option**: By default, reset emails appear in a demo outbox; optionally, configure SMTP to deliver real email messages.
- **User Seeding**: Easily seed your own user to test the flow fully; demo account included for instant exploration.
- **Zero External Requirements**: Run locally with no services beyond Node.js and SQLite.

To try it out locally:

1. Change into `password-reset`, then install and start:
   ```bash
   cd password-reset
   npm install
   npm start
   ```
2. Open `http://localhost:3001` in your browser to use the portal.

To seed your email (for live testing or SMTP), use:
```bash
SEED_USER_EMAIL="you@example.com" npm start
```
You can also configure SMTP via environment variables.

See the `password-reset/README.md` for complete docs, usage, and optional setup.

---



---

### Endpoint Experience Monitoring & Self-Healing (Intune)

**Endpoint Experience Monitoring & Self-Healing** is a PowerShell solution for monitoring endpoint health and running basic self-healing actions, built for deployment via Microsoft Intune Proactive Remediations.

Key features:
- Collects performance and app health signals (boot time, resource usage, Windows Update, Teams health, etc.)
- Calculates a Digital Experience Score (0–100) and health state (Healthy/Warning/Critical)
- When in Critical state, can automatically:
  - Restart Teams
  - Sync Intune policy
  - Clear safe Teams cache and temp files
- Writes structured logs for audit and troubleshooting

**Designed for** Intune Proactive Remediations (SYSTEM context, non-interactive).

- Scripts and log locations:
  - PowerShell scripts: `endpoint-experience-monitoring/scripts/`
  - Example deployment and folder structure detailed in the project [README](endpoint-experience-monitoring/README.md)

See `endpoint-experience-monitoring/README.md` for setup, script descriptions, and Intune deployment guidance.

---

### Access & License Audit (Offline JSON, Python)

**Access & License Audit** is a Python 3 command-line tool for auditing Microsoft 365 or Entra ID users and license assignments from offline JSON exports. No cloud authentication required.

Key features:
- Loads users from a local Microsoft export (`sample_data.json` provided)
- Maps license/SKU IDs to names (if available)
- Flags risky license hygiene (e.g. disabled users with licenses, inactive users, lack of MFA)
- Generates detailed JSON and CSV reports
- Easy to extend with custom audit rules

**How to use:**  
- Simple, step-by-step run instructions in `py-script-project/README.md`
- No Python experience required; just install, prepare the data file, and run

See `py-script-project/README.md` for configuration, input format, and report details.



