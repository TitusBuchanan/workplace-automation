import datetime as dt
import os
import uuid

from celery import Celery
from sqlmodel import select

from app.config import get_settings
from app.db import engine, get_session
from app.integrations import dispatch
from app.models import AuditLog, Blueprint, Device, WorkflowRun

settings = get_settings()
celery_app = Celery("zero_touch", broker=settings.broker_url)


def enqueue_workflow(workflow_id: uuid.UUID, dry_run: bool = False) -> None:
    celery_app.send_task("app.worker.run_workflow", args=[str(workflow_id), dry_run])


@celery_app.task(name="app.worker.run_workflow")
def run_workflow(workflow_id: str, dry_run: bool = False) -> None:
    with get_session() as session:
        run = session.get(WorkflowRun, workflow_id)
        if not run:
            return
        device = session.get(Device, run.device_id)
        blueprint = session.get(Blueprint, run.blueprint_id)
        if not device or not blueprint:
            run.status = "failed"
            run.last_error = "missing device or blueprint"
            session.commit()
            return

        steps = []
        try:
            steps.append({"name": "fetch_blueprint", "status": "ok"})
            if dry_run:
                result_actions = ["dry-run no-op"]
                steps.append({"name": "plan", "status": "ok", "detail": result_actions})
                run.status = "completed"
            else:
                result = dispatch(device.os_type, blueprint.dict(), device.facts)
                if not result.ok:
                    raise RuntimeError(result.error or "provision failed")
                steps.append({"name": "apply", "status": "ok", "detail": result.actions})
                run.status = "completed"
                device.status = "provisioned"
        except Exception as exc:  # pragma: no cover - defensive
            run.status = "failed"
            run.last_error = str(exc)
            steps.append({"name": "error", "status": "failed", "detail": str(exc)})
            device.status = "error"

        run.steps = steps
        run.updated_at = dt.datetime.utcnow()
        session.add(
            AuditLog(
                actor="worker",
                action="workflow_update",
                target_type="workflow",
                target_id=str(run.id),
                message=f"status={run.status}",
            )
        )
        session.commit()
