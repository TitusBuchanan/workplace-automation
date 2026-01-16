"""
Main orchestration for the Microsoft 365 access + license audit tool.

This script:
- Loads config
- Loads an offline JSON export (no Azure required)
- Applies audit rules
- Writes CSV/JSON reports
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Dict, List, Optional, Sequence

from audit_rules import AuditConfig, run_audit
from graph_client import DataSourceError, JsonExportClient
from report_generator import ensure_out_dir, print_console_summary, write_findings_csv, write_findings_json


def _load_yaml_config(path: str) -> Dict[str, Any]:
    """
    Load YAML config if it exists; return {} for missing default config.
    """

    if not path:
        return {}

    if not os.path.exists(path):
        return {}

    try:
        import yaml  # type: ignore
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "PyYAML is not installed, but a config file was provided. "
            "Either install dependencies (pip install -r requirements.txt) or run without --config."
        ) from exc

    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
        if data is None:
            return {}
        if not isinstance(data, dict):
            raise ValueError(f"Config file must contain a YAML mapping/object, got: {type(data)}")
        return data


def _get_cfg(cfg: Dict[str, Any], keys: Sequence[str], default: Any) -> Any:
    cur: Any = cfg
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


def _parse_formats(value: Optional[str], cfg: Dict[str, Any]) -> List[str]:
    if value:
        raw = value
    else:
        raw = _get_cfg(cfg, ["report", "formats"], ["json", "csv"])

    if isinstance(raw, str):
        items = [p.strip().lower() for p in raw.split(",") if p.strip()]
    elif isinstance(raw, list):
        items = [str(p).strip().lower() for p in raw if str(p).strip()]
    else:
        items = ["json", "csv"]

    allowed = {"json", "csv"}
    out = [f for f in items if f in allowed]
    if not out:
        return ["json", "csv"]
    return out


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Audit user access and license usage from an offline JSON export.")
    parser.add_argument(
        "--input",
        default=None,
        help="Path to input JSON export (overrides config).",
    )
    parser.add_argument(
        "--config",
        default="config.yaml",
        help="Path to YAML config file (default: config.yaml).",
    )
    parser.add_argument(
        "--out-dir",
        default=None,
        help="Output directory for reports (overrides config).",
    )
    parser.add_argument(
        "--formats",
        default=None,
        help="Comma-separated formats to generate: csv,json (overrides config).",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)

    script_dir = os.path.dirname(os.path.abspath(__file__))

    # If the user explicitly passes a config path and it doesn't exist, error out.
    if args.config and args.config != "config.yaml" and not os.path.exists(args.config):
        print(f"Config file not found: {args.config}", file=sys.stderr)
        return 2

    try:
        cfg = _load_yaml_config(args.config)
    except Exception as exc:
        print(f"Failed to load config: {exc}", file=sys.stderr)
        return 2

    default_input = os.path.join(script_dir, "sample_data.json")
    input_path = args.input or _get_cfg(cfg, ["input", "path"], default_input)
    if not input_path:
        print("Missing input JSON path. Provide --input or set input.path in config.", file=sys.stderr)
        return 2

    out_dir = args.out_dir or _get_cfg(cfg, ["report", "out_dir"], os.path.join(script_dir, "out"))
    out_dir = ensure_out_dir(str(out_dir))

    inactivity_days = int(_get_cfg(cfg, ["audit", "inactivity_days"], 90))
    formats = _parse_formats(args.formats, cfg)

    try:
        client = JsonExportClient(str(input_path))
        users = client.get_users()
        skus = client.get_skus()
        sku_map = JsonExportClient.build_sku_map(skus)
    except DataSourceError as exc:
        print(f"Input error: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"Unexpected error while loading input: {exc}", file=sys.stderr)
        return 1

    audit_cfg = AuditConfig(inactivity_days=inactivity_days)
    findings = run_audit(users, sku_map, audit_cfg)

    written_paths: List[str] = []
    if "json" in formats:
        written_paths.append(write_findings_json(findings, out_dir))
    if "csv" in formats:
        written_paths.append(write_findings_csv(findings, out_dir))

    print_console_summary(total_users=len(users), findings=findings)
    print("")
    print("Reports written:")
    for p in written_paths:
        print(f"- {p}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

