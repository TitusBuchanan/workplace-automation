# Access & License Audit (Offline JSON, Python)

A small, readable Python 3 tool that audits users and license assignments from a **local JSON export**, flags common license hygiene risks, and generates **CSV + JSON** reports for IT teams.

## What it does
- Loads users from a JSON export (no cloud auth required)
- Loads a SKU catalog (optional) so license IDs can be mapped to friendly names
- Applies simple audit rules (easy to extend)
- Writes reports to disk and prints a short console summary

## Input format (JSON)
The input file must be a JSON object with at least:
- `users`: list of user objects

Optional:
- `skus`: list of SKU objects (for mapping license IDs to names)

Each user should include (recommended):
- `id`
- `displayName`
- `userPrincipalName`
- `accountEnabled` (true/false)
- `assignedLicenses` (list of strings, e.g. `["M365_E3"]`)

Optional fields (enable more rules):
- `lastSignInDateTime` (ISO timestamp string)
- `mfaEnabled` (boolean)

See `sample_data.json` for a working example you can edit.

## Audit rules included
Always available with basic reads:
- **Disabled users with active licenses**: account disabled but still assigned one or more licenses

Optional rules (auto-skip unless the data is present):
- **Inactive users (> N days)**: requires a last sign-in timestamp
- **Licensed users without sign-in activity**: requires sign-in fields to exist in the dataset
- **Users without MFA**: requires an MFA posture field (this project treats it as optional by design)

## Configuration
Copy the example config:

```bash
cp config.example.yaml config.yaml
```

Key settings in `config.yaml`:
- `input.path`: path to your JSON export (defaults to `sample_data.json`)
- `report.out_dir`: where reports are written (default `out/`)
- `report.formats`: `json` and/or `csv`
- `audit.inactivity_days`: used only when sign-in activity is available in the dataset

## Install + run
From this folder:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

python main.py
```

Optional CLI overrides:

```bash
python main.py --input sample_data.json --out-dir out --formats csv,json
```

## Output
The tool writes:
- `out/findings.json`: full structured findings
- `out/findings.csv`: flattened findings for sharing

CSV columns:
- `risk_type`, `severity`, `upn`, `display_name`, `user_id`, `details`, `evidence`, `recommended_action`

Example console summary:

```text
=== Microsoft 365 Access & License Audit Summary ===
Total users scanned: 250
Total findings:      8

Findings by risk type:
- disabled_user_with_licenses: 8

Reports written:
- out/findings.json
- out/findings.csv
```

## Notes / safe scripting practices
- This tool is designed for **read-only auditing**.
- It validates input shape and fails with clear errors when required fields are missing.
