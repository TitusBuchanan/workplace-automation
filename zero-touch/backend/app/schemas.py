import datetime as dt
import uuid
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class EnrollmentTokenCreate(BaseModel):
    ttl_minutes: int = Field(default=30, ge=1, le=24 * 60)
    max_uses: int = Field(default=1, ge=1, le=1000)
    claims: Dict[str, Any] = Field(default_factory=dict)


class EnrollmentTokenOut(BaseModel):
    token: str
    expires_at: dt.datetime
    uses_remaining: int
    enrollment_url: str
    qr_ascii: str


class DeviceRegister(BaseModel):
    token: str
    hostname: str
    os_type: str
    arch: str
    facts: Dict[str, Any] = Field(default_factory=dict)


class DeviceOut(BaseModel):
    id: uuid.UUID
    hostname: str
    os_type: str
    arch: str
    status: str
    blueprint_id: Optional[uuid.UUID]
    last_seen: Optional[dt.datetime]
    facts: Dict[str, Any]


class BlueprintCreate(BaseModel):
    name: str
    description: str = ""
    os_targets: List[str] = Field(default_factory=list)
    packages: Dict[str, Any] = Field(default_factory=dict)
    files: Dict[str, Any] = Field(default_factory=dict)
    users: Dict[str, Any] = Field(default_factory=dict)
    security: Dict[str, Any] = Field(default_factory=dict)


class BlueprintUpdate(BlueprintCreate):
    pass


class BlueprintOut(BlueprintCreate):
    id: uuid.UUID


class WorkflowStart(BaseModel):
    blueprint_id: uuid.UUID
    dry_run: bool = False


class WorkflowStep(BaseModel):
    name: str
    status: str
    detail: Optional[str] = None


class WorkflowOut(BaseModel):
    id: uuid.UUID
    device_id: uuid.UUID
    blueprint_id: uuid.UUID
    status: str
    started_at: dt.datetime
    updated_at: dt.datetime
    steps: List[WorkflowStep] = Field(default_factory=list)
    last_error: Optional[str] = None
