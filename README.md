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