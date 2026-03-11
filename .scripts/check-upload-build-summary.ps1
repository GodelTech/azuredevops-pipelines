<#
.SYNOPSIS
    Verifies that the last step of the last job in every Azure DevOps test pipeline
    references the upload-build-summary helper template.

.DESCRIPTION
    Walks all *.yml files under the .azuredevops folder (excluding testHelpers and CI.yml)
    and checks that the last template: reference in each file resolves to
    '.azuredevops/testHelpers/upload-build-summary.yml'.
    Exits with code 1 if any files fail the check so the build fails.

.PARAMETER AzureDevOpsPath
    Path to the folder that contains Azure DevOps pipeline YAML files.
    Defaults to '.azuredevops' relative to the repository root (one level above this script).

.EXAMPLE
    # Run from the repository root
    .\.scripts\check-upload-build-summary.ps1

    # Run against a custom folder
    .\.scripts\check-upload-build-summary.ps1 -AzureDevOpsPath 'C:\repo\.azuredevops'
#>
param(
    [string]$AzureDevOpsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Resolve paths ─────────────────────────────────────────────────────────────────────────────
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if ($AzureDevOpsPath -eq '') {
    $AzureDevOpsPath = Join-Path $repoRoot '.azuredevops'
}

# The canonical repo-relative path that must be the last template step
$uploadSummaryTemplatePath = '.azuredevops/testHelpers/upload-build-summary.yml'

# ── Helper ────────────────────────────────────────────────────────────────────────────────────

function Get-LastRepoRelativeTemplatePath {
    <#
    Finds the last 'template:' reference in a YAML pipeline file and returns
    its path relative to the repository root (forward-slash separated).
    Returns $null if no template references are found.
    Handles single-quoted, double-quoted, and unquoted template values.
    #>
    param([string]$content, [string]$filePath, [string]$repoRoot)

    $fileDir = [System.IO.Path]::GetDirectoryName($filePath)

    $templateMatches = [regex]::Matches($content, "template:\s+'([^']+)'|template:\s+`"([^`"]+)`"|template:\s+(\S+)")
    if ($templateMatches.Count -eq 0) { return $null }

    $lastMatch = $templateMatches[$templateMatches.Count - 1]
    $ref = if ($lastMatch.Groups[1].Success) { $lastMatch.Groups[1].Value }
           elseif ($lastMatch.Groups[2].Success) { $lastMatch.Groups[2].Value }
           else { $lastMatch.Groups[3].Value }

    $absolute = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($fileDir, $ref))
    return $absolute.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
}

# ── Scan pipeline files ───────────────────────────────────────────────────────────────────────────

$files = Get-ChildItem -Path $AzureDevOpsPath -Recurse -Filter '*.yml' |
    Where-Object {
        $_.FullName -notmatch '[/\\]testHelpers[/\\]' -and
        $_.Name -ne 'CI.yml'
    }

$issues = @()

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    $lastTemplate = Get-LastRepoRelativeTemplatePath -content $content -filePath $file.FullName -repoRoot $repoRoot

    if ($lastTemplate -ne $uploadSummaryTemplatePath) {
        $actual = if ($lastTemplate) { "'$lastTemplate'" } else { 'no template reference found' }
        $issues += [PSCustomObject]@{ File = $file.FullName; Actual = $actual }
    }
}

# ── Report results ──────────────────────────────────────────────────────────────────────────────

if ($issues.Count -eq 0) {
    Write-Host "All files have '$uploadSummaryTemplatePath' as the last step." -ForegroundColor Green
} else {
    Write-Host "The following files do not have '$uploadSummaryTemplatePath' as the last step of the last job:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  $($issue.File)" -ForegroundColor Yellow
        Write-Host "    last template: $($issue.Actual)" -ForegroundColor White
    }
}

$color = if ($issues.Count -eq 0) { 'Green' } else { 'Red' }
Write-Host "Check Upload Build Summary: $($issues.Count) error(s)" -ForegroundColor $color

if ($issues.Count -gt 0) { exit 1 }
