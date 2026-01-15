import datetime as dt
import secrets
from typing import List

import qrcode
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import select

from app import schemas
from app.db import get_session
from app.deps import require_api_key
from app.models import AuditLog, Device, EnrollmentToken

router = APIRouter(prefix="/enrollment", tags=["enrollment"])


def _make_qr_ascii(content: str) -> str:
    qr = qrcode.QRCode(border=1)
    qr.add_data(content)
    qr.make(fit=True)
    lines: List[str] = []
    for row in qr.get_matrix():
        line = "".join("██" if cell else "  " for cell in row)
        lines.append(line)
    return "\n".join(lines)


@router.post("/tokens", response_model=schemas.EnrollmentTokenOut)
def create_token(payload: schemas.EnrollmentTokenCreate, session=Depends(get_session), _: None = Depends(require_api_key)):
    token_value = secrets.token_urlsafe(24)
    expires_at = dt.datetime.utcnow() + dt.timedelta(minutes=payload.ttl_minutes)
    token = EnrollmentToken(
        token=token_value,
        expires_at=expires_at,
        uses_remaining=payload.max_uses,
        claims=payload.claims,
    )
    session.add(token)
    session.add(
        AuditLog(
            actor="api",
            action="create_token",
            target_type="enrollment",
            target_id=str(token.id),
            message=f"ttl={payload.ttl_minutes} uses={payload.max_uses}",
        )
    )
    session.commit()
    session.refresh(token)
    enrollment_url = f"https://api.localhost/enroll?token={token_value}"
    return schemas.EnrollmentTokenOut(
        token=token_value,
        expires_at=expires_at,
        uses_remaining=payload.max_uses,
        enrollment_url=enrollment_url,
        qr_ascii=_make_qr_ascii(enrollment_url),
    )


@router.post("/register", response_model=schemas.DeviceOut)
def register_device(payload: schemas.DeviceRegister, session=Depends(get_session)):
    token = session.exec(
        select(EnrollmentToken).where(EnrollmentToken.token == payload.token)
    ).first()
    if not token:
        raise HTTPException(status_code=404, detail="Token not found")
    if token.expires_at < dt.datetime.utcnow():
        raise HTTPException(status_code=400, detail="Token expired")
    if token.uses_remaining <= 0:
        raise HTTPException(status_code=400, detail="Token exhausted")

    device = Device(
        hostname=payload.hostname,
        os_type=payload.os_type,
        arch=payload.arch,
        facts=payload.facts,
        enrollment_token_id=token.id,
        status="enrolled",
        last_seen=dt.datetime.utcnow(),
        blueprint_id=payload.facts.get("blueprint_id"),
    )
    token.uses_remaining -= 1
    session.add(device)
    session.add(
        AuditLog(
            actor=payload.hostname,
            action="register_device",
            target_type="device",
            target_id=str(device.id),
            message=f"os={payload.os_type} arch={payload.arch}",
        )
    )
    session.commit()
    session.refresh(device)
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
