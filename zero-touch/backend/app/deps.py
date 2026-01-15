from fastapi import Depends, Header, HTTPException, status

from app.config import get_settings


def require_api_key(x_api_key: str = Header(default=None)) -> None:
    settings = get_settings()
    if not x_api_key or x_api_key != settings.api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key"
        )


def optional_api_key(x_api_key: str = Header(default=None)) -> str:
    return x_api_key or ""
