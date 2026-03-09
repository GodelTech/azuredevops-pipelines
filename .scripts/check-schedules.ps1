$scheduleBlock = @"
schedules:
  - cron: '0 0 1 * *'
    displayName: 'Monthly check'
    branches:
      include:
        - main
    always: true
"@

$azureDevOpsPath = Join-Path (Join-Path $PSScriptRoot '..') '.azuredevops'
$files = Get-ChildItem -Path $azureDevOpsPath -Recurse -Filter '*.yml' |
    Where-Object { $_.FullName -notlike '*\testHelpers\*' }

$missing = @()

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    if ($content -notmatch [regex]::Escape($scheduleBlock)) {
        $missing += $file.FullName
    }
}

if ($missing.Count -eq 0) {
    Write-Host "All files contain the schedule block." -ForegroundColor Green
} else {
    Write-Host "The following files are missing the schedule block:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    exit 1
}
