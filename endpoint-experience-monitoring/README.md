# Endpoint Experience Monitoring & Self-Healing (Intune)

PowerShell-only Digital Workplace Experience Monitoring + basic self-healing, designed for **Microsoft Intune Proactive Remediations** (SYSTEM context, non-interactive).

## What this project does

- Collects basic endpoint performance + app health signals (boot time, CPU/memory, disk, Windows Update, Teams process health)
- Calculates a simple **Digital Experience Score (0–100)** and health state (**Healthy / Warning / Critical**)
- When **Critical**, runs a small set of safe remediations:
  - Restart Microsoft Teams (best-effort; SYSTEM limitations apply)
  - Trigger Intune policy sync
  - Clear Teams cache (safe user-profile paths only)
  - Basic disk cleanup (safe temp locations only)
- Writes a local JSONL log for troubleshooting and audit

## Folder layout

Repo layout:

- `endpoint-experience-monitoring/scripts/`
  - `Get-EndpointExperienceMetrics.ps1`
  - `Invoke-ExperienceScoring.ps1`
  - `Invoke-EndpointSelfHeal.ps1`
  - `Write-ExperienceLog.ps1`

Device layout (staged):

- `C:\ProgramData\WorkplaceAutomation\EndpointExperience\Scripts\`
- `C:\ProgramData\WorkplaceAutomation\EndpointExperience\Logs\`

## How it works (high level)

1. `Get-EndpointExperienceMetrics.ps1` collects metrics and returns a PowerShell object.
2. `Invoke-ExperienceScoring.ps1` turns metrics into:
   - `Score` (0–100)
   - `HealthState` (Healthy/Warning/Critical)
   - `Reasons` (why points were deducted)
3. `Invoke-EndpointSelfHeal.ps1` runs **only when Critical**, then re-scores to capture improvement.
4. `Write-ExperienceLog.ps1` writes JSONL log entries under ProgramData.

## Intune Proactive Remediations deployment

Intune Proactive Remediations supports uploading **two scripts** (Detection + Remediation). This project assumes you **stage** the scripts to ProgramData first (for example via a Win32 app or a one-time install script).

### 1) Stage the scripts

Stage these files to the endpoint:

- `C:\ProgramData\WorkplaceAutomation\EndpointExperience\Scripts\Get-EndpointExperienceMetrics.ps1`
- `C:\ProgramData\WorkplaceAutomation\EndpointExperience\Scripts\Invoke-ExperienceScoring.ps1`
- `C:\ProgramData\WorkplaceAutomation\EndpointExperience\Scripts\Invoke-EndpointSelfHeal.ps1`
- `C:\ProgramData\WorkplaceAutomation\EndpointExperience\Scripts\Write-ExperienceLog.ps1`

Practical staging options:

- **Win32 app (recommended)**: package the `Scripts\` folder, then copy into ProgramData during install.
- **One-time script**: use an Intune PowerShell script to create the folders and write/copy the files (less ideal to maintain).

### 2) Detection script (uploaded to Intune)

Create a short detection script in Intune that calls the staged scoring script:

```powershell
$script = Join-Path $env:ProgramData 'WorkplaceAutomation\EndpointExperience\Scripts\Invoke-ExperienceScoring.ps1'
& $script -AsIntuneDetection
exit $LASTEXITCODE
```

Expected behavior:
- **Exit 0** when `HealthState` is **Healthy**
- **Exit 1** when remediation is required (**Critical**)

Note:
- **Warning** does **not** trigger remediation in this project (by design/scope).

### 3) Remediation script (uploaded to Intune)

Create a short remediation script in Intune that calls the staged self-heal script:

```powershell
$script = Join-Path $env:ProgramData 'WorkplaceAutomation\EndpointExperience\Scripts\Invoke-EndpointSelfHeal.ps1'
& $script
exit $LASTEXITCODE
```

## Logging

Default log path:

- `C:\ProgramData\WorkplaceAutomation\EndpointExperience\Logs\experience.jsonl`

Format:
- JSONL (one JSON object per line)
- Fields include `timestamp`, `level`, `message`, and optional `data`

Example log entry:

```json
{"timestamp":"2026-01-15T21:02:18.1234567Z","level":"INFO","message":"Calculated endpoint experience score.","data":{"Score":72,"HealthState":"Warning","Reasons":["System drive free space below 15%."]}}
```

## Remediation details (what it actually does)

When health is **Critical**, `Invoke-EndpointSelfHeal.ps1` runs these steps (all best-effort, all logged):

- **Restart Microsoft Teams**: stops common Teams processes. If an executable path is detectable, it attempts to start it again, but **running as SYSTEM may not re-open Teams UI for the signed-in user**.
- **Trigger Intune policy sync**: starts a scheduled task under `\Microsoft\Windows\EnterpriseMgmt\...` (prefers `PushLaunch`).
- **Clear Teams cache (safe paths only)**: deletes known cache directories under each user profile (`C:\Users\*\...`) for classic Teams and the new Teams package cache paths.
- **Basic disk cleanup**: deletes contents of safe temp locations (`C:\Windows\Temp`, SYSTEM `%TEMP%`, and `C:\Users\*\AppData\Local\Temp`).

## Tuning scoring

Update the thresholds/weights in:

- `endpoint-experience-monitoring/scripts/Invoke-ExperienceScoring.ps1`

The scoring is intentionally straightforward and based on:
- System drive free space
- CPU/memory utilization (point-in-time)
- Uptime days
- Windows Update service status + reboot pending

## Runtime considerations

- **Non-interactive / SYSTEM**: designed for Intune Proactive Remediations execution context.
- **Optional Windows Update pending count**: some environments block or slow COM-based update searches; this is optional via `-IncludePendingUpdateCount`.

## Operational notes (help desk friendly)

- **Where to look first**: open the JSONL log and search for `HealthState` or `Self-heal` messages.
- **Teams remediation expectations**: stopping Teams processes + clearing cache can help with stuck sign-in/UI issues, but **SYSTEM context cannot guarantee re-launch into the interactive user session**.
- **Disk cleanup safety**: this project only clears temp locations; it does not run `cleanmgr`, DISM, or component store cleanup.

## Problems this targets (real-world)

- Low disk space impacting performance/app behavior
- High CPU / memory pressure (basic signal)
- Long uptime + pending reboot signals (stability issues)
- Windows Update service not running / reboot pending
- Teams process/cache issues (best-effort remediation under SYSTEM)

