"""
Offline data loader (JSON input).

Responsibilities:
- Load users and SKUs from a local JSON export (no cloud auth required)
- Provide simple accessors that return Python dicts/lists
"""

from __future__ import annotations

import json
import os
from typing import Any, Dict, List, Optional


class DataSourceError(RuntimeError):
    """Raised when the input dataset is missing/invalid."""


class JsonExportClient:
    """
    Loads an offline JSON export.

    Expected top-level keys:
    - users: list[dict]
    - skus:  list[dict] (optional)
    """

    def __init__(self, input_path: str) -> None:
        self._input_path = input_path
        self._data: Optional[Dict[str, Any]] = None

    def _load(self) -> Dict[str, Any]:
        if self._data is not None:
            return self._data

        if not self._input_path:
            raise DataSourceError("Missing input path.")
        if not os.path.exists(self._input_path):
            raise DataSourceError(f"Input file not found: {self._input_path}")

        try:
            with open(self._input_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except json.JSONDecodeError as exc:
            raise DataSourceError(f"Invalid JSON in input file: {self._input_path} ({exc})") from exc

        if not isinstance(data, dict):
            raise DataSourceError("Input JSON must be an object at the top level.")

        self._data = data
        return data

    def get_users(self) -> List[Dict[str, Any]]:
        data = self._load()
        users = data.get("users", [])
        if not isinstance(users, list):
            raise DataSourceError("Input JSON 'users' must be a list.")
        return [u for u in users if isinstance(u, dict)]

    def get_skus(self) -> List[Dict[str, Any]]:
        data = self._load()
        skus = data.get("skus", [])
        if skus is None:
            return []
        if not isinstance(skus, list):
            raise DataSourceError("Input JSON 'skus' must be a list when present.")
        return [s for s in skus if isinstance(s, dict)]

    @staticmethod
    def build_sku_map(skus: List[Dict[str, Any]]) -> Dict[str, str]:
        """
        Build a mapping of skuId -> skuPartNumber (or displayName).
        """

        sku_map: Dict[str, str] = {}
        for sku in skus:
            sku_id = str(sku.get("skuId", "")).strip()
            part = str(sku.get("skuPartNumber", "")).strip()
            if sku_id:
                sku_map[sku_id] = part or str(sku.get("displayName", "")).strip() or sku_id
        return sku_map

