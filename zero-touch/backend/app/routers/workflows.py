import datetime as dt
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import select

from app import schemas
from app.db import get_session
from app.deps import require_api_key
from app.models import AuditLog, Blueprint, Device, WorkflowRun
from app.worker import enqueue_workflow

router = APIRouter(prefix="/workflows", tags=["workflows"])


@router.post("/devices/{device_id}", response_model=schemas.WorkflowOut)
def start_workflow(device_id: str, payload: schemas.WorkflowStart, session=Depends(get_session), _: None = Depends(require_api_key)):
    device = session.get(Device, device_id)
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    blueprint = session.get(Blueprint, payload.blueprint_id)
    if not blueprint:
        raise HTTPException(status_code=404, detail="Blueprint not found")

    run = WorkflowRun(
        device_id=device.id,
        blueprint_id=blueprint.id,
        status="queued",
        steps=[],
    )
    device.status = "provisioning"
    session.add(run)
    session.add(
        AuditLog(
            actor="api",
            action="start_workflow",
            target_type="workflow",
            target_id=str(run.id),
            message=f"device={device.hostname} blueprint={blueprint.name}",
        )
    )
    session.commit()
    enqueue_workflow(run.id, dry_run=payload.dry_run)
    return schemas.WorkflowOut(
        id=run.id,
        device_id=run.device_id,
        blueprint_id=run.blueprint_id,
        status=run.status,
        started_at=run.started_at,
        updated_at=run.updated_at,
        steps=[],
        last_error=None,
    )


@router.get("/{workflow_id}", response_model=schemas.WorkflowOut)
def get_workflow(workflow_id: uuid.UUID, session=Depends(get_session), _: None = Depends(require_api_key)):
    run = session.get(WorkflowRun, workflow_id)
    if not run:
        raise HTTPException(status_code=404, detail="Workflow not found")
    return schemas.WorkflowOut(
        id=run.id,
        device_id=run.device_id,
        blueprint_id=run.blueprint_id,
        status=run.status,
        started_at=run.started_at,
        updated_at=run.updated_at,
        steps=[
            schemas.WorkflowStep(**step) for step in (run.steps or [])
        ],
        last_error=run.last_error,
    )
