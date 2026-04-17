<#
.SYNOPSIS
    Verifies that every Azure DevOps pipeline YAML file contains the required schedule block.

.DESCRIPTION
    Walks all *.yml files under the .azuredevops folder (excluding testHelpers) and checks
    that each one contains the canonical monthly schedule block.  Exits with code 1 if any
    files are missing the block so the build fails.

.PARAMETER AzureDevOpsPath
    Path to the folder that contains Azure DevOps pipeline YAML files.
    Defaults to '.azuredevops' relative to the repository root (one level above this script).

.EXAMPLE
    # Run from the repository root
    .\.scripts\check-schedules.ps1

    # Run against a custom folder
    .\.scripts\check-schedules.ps1 -AzureDevOpsPath 'C:\repo\.azuredevops'
#>
param(
    [string]$AzureDevOpsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Resolve paths -----------------------------------------------------------------------------
if ($AzureDevOpsPath -eq '') {
    $AzureDevOpsPath = Join-Path (Join-Path $PSScriptRoot '..') '.azuredevops'
}

# -- Required schedule block ------------------------------------------------------------
# Every pipeline must include this exact schedule so they are executed at least once a month
# even when no code changes occur (always: true ensures the run happens regardless of changes).
$scheduleBlock = @"
schedules:
  - cron: '0 0 1 * *'
    displayName: 'Monthly check'
    branches:
      include:
        - main
    always: true
"@

# -- Scan pipeline files ---------------------------------------------------------------------------
$files = Get-ChildItem -Path $AzureDevOpsPath -Recurse -Filter '*.yml' |
    Where-Object { $_.FullName -notmatch '[/\\]testHelpers[/\\]' }

$missing = @()

$normalizedScheduleBlock = $scheduleBlock -replace '\r\n', "`n"

foreach ($file in $files) {
    $content = (Get-Content -Path $file.FullName -Raw) -replace '\r\n', "`n"
    if ($content -notmatch [regex]::Escape($normalizedScheduleBlock)) {
        $missing += $file.FullName
    }
}

# -- Report results ------------------------------------------------------------------------------
if ($missing.Count -eq 0) {
    Write-Host "All files contain the schedule block." -ForegroundColor Green
} else {
    Write-Host "The following files are missing the schedule block:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Required schedule block:" -ForegroundColor Cyan
    Write-Host $scheduleBlock -ForegroundColor Cyan
}

$color = if ($missing.Count -eq 0) { 'Green' } else { 'Red' }
Write-Host "Check Schedules: $($missing.Count) error(s)" -ForegroundColor $color

if ($missing.Count -gt 0) { exit 1 }
