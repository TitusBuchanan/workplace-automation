from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import select

from app import schemas
from app.db import get_session
from app.deps import require_api_key
from app.models import Device

router = APIRouter(prefix="/devices", tags=["devices"])


@router.get("", response_model=list[schemas.DeviceOut])
def list_devices(session=Depends(get_session), _: None = Depends(require_api_key)):
    devices = session.exec(select(Device)).all()
    return [
        schemas.DeviceOut(
            id=d.id,
            hostname=d.hostname,
            os_type=d.os_type,
            arch=d.arch,
            status=d.status,
            blueprint_id=d.blueprint_id,
            last_seen=d.last_seen,
            facts=d.facts,
        )
        for d in devices
    ]


@router.get("/{device_id}", response_model=schemas.DeviceOut)
def get_device(device_id: str, session=Depends(get_session), _: None = Depends(require_api_key)):
    device = session.get(Device, device_id)
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    return schemas.DeviceOut(
        id=device.id,
        hostname=device.hostname,
        os_type=device.os_type,
        arch=device.arch,
        status=device.status,
        blueprint_id=device.blueprint_id,
        last_seen=device.last_seen,
        facts=device.facts,
    )
