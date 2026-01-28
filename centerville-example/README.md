# entra + graph + powershell learning lab (phased)

this folder is my hands-on lab for entra + microsoft graph using powershell.
it’s split into phases so i can run things step by step and actually see what’s happening.

## Prereqs

- powershell 7+
- a safe lab tenant (don’t do this in prod)
- microsoft graph powershell sdk (phase 0 can install it)

## Run order

from repo root:

```powershell
./centerville-example/00-MacSetUpForGraph.ps1
./centerville-example/01-EntraBasics.ps1 -TenantDomain "<yourTenantDomain>" -Prefix "LAB"
./centerville-example/02-DeviceCodeAndGraph.ps1 -TenantId "<tenantGuidOrDomain>" -ClientId "<clientId>" -CallGraph
./centerville-example/03-GraphPowerShellBasics.ps1 -Prefix "LAB"
./centerville-example/04-SimulateFailures.ps1 -TenantDomain "<yourTenantDomain>" -Prefix "LAB"

# optional (extras)
./centerville-example/extras/05-Rehearse.ps1
./centerville-example/extras/06-QuickReview.ps1 -TenantId "<tenantGuidOrDomain>" -ClientId "<clientId>" -Prefix "LAB"
```