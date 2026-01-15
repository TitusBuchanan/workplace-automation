from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import models
from app.db import init_db
from app.routers import blueprints, devices, enrollment, workflows


def create_app() -> FastAPI:
    app = FastAPI(title="Zero Touch Provisioning API", version="0.1.0")

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.on_event("startup")
    def _startup() -> None:
        init_db()

    @app.get("/healthz")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    app.include_router(enrollment.router)
    app.include_router(devices.router)
    app.include_router(blueprints.router)
    app.include_router(workflows.router)
    return app


app = create_app()
