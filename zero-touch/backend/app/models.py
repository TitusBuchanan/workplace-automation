import datetime as dt
import uuid
from typing import Any, Dict, List, Optional

from sqlalchemy import JSON, Column
from sqlmodel import Field, Relationship, SQLModel


class EnrollmentToken(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    token: str = Field(index=True, unique=True)
    expires_at: dt.datetime
    uses_remaining: int = Field(default=1)
    created_by: str = Field(default="system")
    claims: Dict[str, Any] = Field(sa_column=Column(JSON), default_factory=dict)
    devices: List["Device"] = Relationship(back_populates="enrollment_token")


class Blueprint(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    name: str = Field(index=True)
    description: str = Field(default="")
    os_targets: List[str] = Field(sa_column=Column(JSON), default_factory=list)
    packages: Dict[str, Any] = Field(sa_column=Column(JSON), default_factory=dict)
    files: Dict[str, Any] = Field(sa_column=Column(JSON), default_factory=dict)
    users: Dict[str, Any] = Field(sa_column=Column(JSON), default_factory=dict)
    security: Dict[str, Any] = Field(sa_column=Column(JSON), default_factory=dict)
    devices: List["Device"] = Relationship(back_populates="blueprint")
    workflows: List["WorkflowRun"] = Relationship(back_populates="blueprint")


class Device(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    hostname: str
    os_type: str
    arch: str
    status: str = Field(default="pending")
    last_seen: Optional[dt.datetime] = None
    blueprint_id: Optional[uuid.UUID] = Field(default=None, foreign_key="blueprint.id")
    enrollment_token_id: Optional[uuid.UUID] = Field(
        default=None, foreign_key="enrollmenttoken.id"
    )
    facts: Dict[str, Any] = Field(sa_column=Column(JSON), default_factory=dict)

    blueprint: Optional[Blueprint] = Relationship(back_populates="devices")
    enrollment_token: Optional[EnrollmentToken] = Relationship(
        back_populates="devices"
    )
    workflows: List["WorkflowRun"] = Relationship(back_populates="device")


class WorkflowRun(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    device_id: uuid.UUID = Field(foreign_key="device.id")
    blueprint_id: uuid.UUID = Field(foreign_key="blueprint.id")
    status: str = Field(default="queued")
    steps: List[Dict[str, Any]] = Field(sa_column=Column(JSON), default_factory=list)
    started_at: dt.datetime = Field(default_factory=dt.datetime.utcnow)
    updated_at: dt.datetime = Field(default_factory=dt.datetime.utcnow)
    last_error: Optional[str] = None

    device: Device = Relationship(back_populates="workflows")
    blueprint: Blueprint = Relationship(back_populates="workflows")


class AuditLog(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    actor: str
    action: str
    target_type: str
    target_id: Optional[str] = None
    message: str = Field(default="")
    created_at: dt.datetime = Field(default_factory=dt.datetime.utcnow)
