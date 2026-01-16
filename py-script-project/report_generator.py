"""
Report generation for audit findings.

Outputs:
- JSON (machine-readable, full fidelity)
- CSV (easy to share with IT teams)
"""

from __future__ import annotations

import csv
import json
import os
from collections import Counter
from typing import Any, Dict, List, Sequence


Finding = Dict[str, Any]


CSV_COLUMNS: Sequence[str] = (
    "risk_type",
    "severity",
    "upn",
    "display_name",
    "user_id",
    "details",
    "evidence",
    "recommended_action",
)


def ensure_out_dir(path: str) -> str:
    path = path.strip() or "out"
    os.makedirs(path, exist_ok=True)
    return path


def write_findings_json(findings: List[Finding], out_dir: str, filename: str = "findings.json") -> str:
    out_path = os.path.join(out_dir, filename)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(findings, f, indent=2, sort_keys=False)
    return out_path


def write_findings_csv(findings: List[Finding], out_dir: str, filename: str = "findings.csv") -> str:
    out_path = os.path.join(out_dir, filename)
    with open(out_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(CSV_COLUMNS), extrasaction="ignore")
        writer.writeheader()
        for finding in findings:
            row = dict(finding)
            # Keep evidence readable in CSV by serializing to compact JSON.
            if isinstance(row.get("evidence"), (dict, list)):
                row["evidence"] = json.dumps(row["evidence"], ensure_ascii=False)
            writer.writerow(row)
    return out_path


def print_console_summary(total_users: int, findings: List[Finding]) -> None:
    print("")
    print("=== Microsoft 365 Access & License Audit Summary ===")
    print(f"Total users scanned: {total_users}")
    print(f"Total findings:      {len(findings)}")

    counts = Counter((f.get("risk_type") or "unknown") for f in findings)
    if counts:
        print("")
        print("Findings by risk type:")
        for risk_type, count in counts.most_common():
            print(f"- {risk_type}: {count}")
    else:
        print("")
        print("No findings detected.")

