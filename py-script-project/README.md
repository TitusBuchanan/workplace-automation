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


## Step-by-Step Guide: Using This Audit Tool

Whether you're technical or new to auditing, follow these easy steps to complete your Microsoft 365 access & license check:

1. **Download or Clone the Project**
   - If you haven’t yet, click the green “Code” button on GitHub and select **Download ZIP** or, if you use Git, copy the URL and run:  
     ```
     git clone https://github.com/YOUR_ORG/py-script-project.git
     ```
   - Unzip or open the folder where you downloaded.

2. **Open Your Terminal or Command Prompt**
   - On Windows: Search for “Command Prompt” or “PowerShell” and open it.
   - On Mac: Open the “Terminal” from Applications → Utilities.
   - On Linux: Open your preferred terminal emulator.

3. **Navigate to the Project Folder**
   - Use the `cd` command:
     ```
     cd path/to/py-script-project
     ```
   - Replace `path/to/py-script-project` with the actual folder path.

4. **Set Up Python (one time only)**
   - These steps make sure you have all the required tools in a safe “virtual environment.”
     ```
     python3 -m venv .venv
     ```
     - (If `python3` doesn’t work, try just `python`)
     - Then activate it:
       - On Mac/Linux:
         ```
         source .venv/bin/activate
         ```
       - On Windows:
         ```
         .venv\Scripts\activate
         ```

5. **Install Required Libraries**
   - Run:
     ```
     pip install -r requirements.txt
     ```

6. **Prepare Your Data File**
   - Place your exported Microsoft 365 audit data (for example, `sample_data.json`) in the project folder.
   - If you’re not sure how to export data from Microsoft 365 or Entra, see your admin guide or ask your IT team for a user export file.

7. **Run the Audit**
   - Run the main script with default settings:
     ```
     python main.py
     ```
   - If you want to specify your data file:
     ```
     python main.py --input my_export.json
     ```
   - You can also set where results will be saved:
     ```
     python main.py --input my_export.json --out-dir results/
     ```

8. **View Results**
   - After the script finishes, check the `out/` folder (or your chosen directory).
   - Open `findings.json` for a detailed report, or `findings.csv` to view in Excel or Google Sheets.
   - Look for the console summary to quickly see any major findings.

9. **Share or Take Action**
   - You can send the CSV to others, include the summary in a report, or follow your organization’s next steps based on the findings.

---

**Need help?**
- If you’re stuck, double-check each step above.
- For technical help, you can open an issue on GitHub 

*You don’t need to be a developer to use this tool! Just follow these steps and you’ll be able to audit user access and licenses safely and efficiently.*

