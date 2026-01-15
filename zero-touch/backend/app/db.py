from contextlib import contextmanager
from sqlmodel import SQLModel, create_engine, Session

from app.config import get_settings


settings = get_settings()
engine = create_engine(settings.database_url, echo=False)


def init_db() -> None:
    SQLModel.metadata.create_all(engine)


@contextmanager
def get_session() -> Session:
    session = Session(engine)
    try:
        yield session
    finally:
        session.close()
