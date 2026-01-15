from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import select

from app import schemas
from app.db import get_session
from app.deps import require_api_key
from app.models import AuditLog, Blueprint

router = APIRouter(prefix="/blueprints", tags=["blueprints"])


@router.post("", response_model=schemas.BlueprintOut)
def create_blueprint(payload: schemas.BlueprintCreate, session=Depends(get_session), _: None = Depends(require_api_key)):
    bp = Blueprint(**payload.dict())
    session.add(bp)
    session.add(
        AuditLog(
            actor="api",
            action="create_blueprint",
            target_type="blueprint",
            target_id=str(bp.id),
            message=payload.name,
        )
    )
    session.commit()
    session.refresh(bp)
    return schemas.BlueprintOut(**bp.dict())


@router.get("", response_model=list[schemas.BlueprintOut])
def list_blueprints(session=Depends(get_session), _: None = Depends(require_api_key)):
    blueprints = session.exec(select(Blueprint)).all()
    return [schemas.BlueprintOut(**bp.dict()) for bp in blueprints]


@router.get("/{blueprint_id}", response_model=schemas.BlueprintOut)
def get_blueprint(blueprint_id: str, session=Depends(get_session), _: None = Depends(require_api_key)):
    bp = session.get(Blueprint, blueprint_id)
    if not bp:
        raise HTTPException(status_code=404, detail="Blueprint not found")
    return schemas.BlueprintOut(**bp.dict())


@router.put("/{blueprint_id}", response_model=schemas.BlueprintOut)
def update_blueprint(blueprint_id: str, payload: schemas.BlueprintUpdate, session=Depends(get_session), _: None = Depends(require_api_key)):
    bp = session.get(Blueprint, blueprint_id)
    if not bp:
        raise HTTPException(status_code=404, detail="Blueprint not found")
    for key, value in payload.dict().items():
        setattr(bp, key, value)
    session.add(
        AuditLog(
            actor="api",
            action="update_blueprint",
            target_type="blueprint",
            target_id=str(bp.id),
            message=payload.name,
        )
    )
    session.commit()
    session.refresh(bp)
    return schemas.BlueprintOut(**bp.dict())


@router.delete("/{blueprint_id}")
def delete_blueprint(blueprint_id: str, session=Depends(get_session), _: None = Depends(require_api_key)):
    bp = session.get(Blueprint, blueprint_id)
    if not bp:
        raise HTTPException(status_code=404, detail="Blueprint not found")
    session.delete(bp)
    session.add(
        AuditLog(
            actor="api",
            action="delete_blueprint",
            target_type="blueprint",
            target_id=str(bp.id),
            message=bp.name,
        )
    )
    session.commit()
    return {"status": "deleted"}
