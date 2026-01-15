import os
from functools import lru_cache


class Settings:
    api_key: str = os.getenv("API_KEY", "changeme-api-key")
    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql://zero_touch:zero_touch@localhost:5432/zero_touch",
    )
    broker_url: str = os.getenv("BROKER_URL", "redis://localhost:6379/0")
    service_name: str = os.getenv("SERVICE_NAME", "zero-touch-api")
    issuer: str = os.getenv("ISSUER", "zero-touch")


@lru_cache
def get_settings() -> Settings:
    return Settings()
