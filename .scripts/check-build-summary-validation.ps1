<#
.SYNOPSIS
    Verifies that the last step of the last job in every Azure DevOps test pipeline
    references the build-summary-validation helper template.

.DESCRIPTION
    Walks all *.yml files under the .azuredevops folder (excluding testHelpers and CI.yml)
    and checks that the last template: reference in each file resolves to either
    '.azuredevops/testHelpers/build-summary-validation.yml' or
    '.azuredevops/testHelpers/build-summary-validation.job.yml'.
    Exits with code 1 if any files fail the check so the build fails.

.PARAMETER AzureDevOpsPath
    Path to the folder that contains Azure DevOps pipeline YAML files.
    Defaults to '.azuredevops' relative to the repository root (one level above this script).

.EXAMPLE
    # Run from the repository root
    .\.scripts\check-build-summary-validation.ps1

    # Run against a custom folder
    .\.scripts\check-build-summary-validation.ps1 -AzureDevOpsPath 'C:\repo\.azuredevops'
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

# The canonical repo-relative paths that must be the last template step
$validBuildSummaryValidationTemplatePaths = @(
    '.azuredevops/testHelpers/build-summary-validation.yml',
    '.azuredevops/testHelpers/build-summary-validation.job.yml'
)

# ── Helper ────────────────────────────────────────────────────────────────────────────────────

function Get-LastRepoRelativeTemplatePath {
    <#
    .SYNOPSIS
        Finds the last 'template:' reference in a YAML pipeline file.
    .DESCRIPTION
        Returns the path of the last template reference relative to the repository root
        (forward-slash separated). Returns $null if no template references are found.
        Handles single-quoted, double-quoted, and unquoted template values.
    .PARAMETER Content
        Raw text content of the YAML pipeline file.
    .PARAMETER FilePath
        Absolute path to the YAML pipeline file, used to resolve relative template references.
    .PARAMETER RepoRoot
        Absolute path to the repository root, used to compute the repo-relative output path.
    .OUTPUTS
        [string] Repo-relative forward-slash path of the last template reference, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $fileDir = [System.IO.Path]::GetDirectoryName($FilePath)

    $templateMatches = [regex]::Matches($Content, "template:\s+'([^']+)'|template:\s+`"([^`"]+)`"|template:\s+(\S+)")
    if ($templateMatches.Count -eq 0) { return $null }

    $lastMatch = $templateMatches[$templateMatches.Count - 1]
    $ref = if ($lastMatch.Groups[1].Success) { $lastMatch.Groups[1].Value }
           elseif ($lastMatch.Groups[2].Success) { $lastMatch.Groups[2].Value }
           else { $lastMatch.Groups[3].Value }

    $absolute = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($fileDir, $ref))
    return $absolute.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
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
    $lastTemplate = Get-LastRepoRelativeTemplatePath -Content $content -FilePath $file.FullName -RepoRoot $repoRoot

    if ($lastTemplate -notin $validBuildSummaryValidationTemplatePaths) {
        $actual = if ($lastTemplate) { "'$lastTemplate'" } else { 'no template reference found' }
        $issues += [PSCustomObject]@{ File = $file.FullName; Actual = $actual }
    }
}

# ── Report results ──────────────────────────────────────────────────────────────────────────────

if ($issues.Count -eq 0) {
    Write-Host "All files have a valid build summary validation template as the last step." -ForegroundColor Green
} else {
    Write-Host "The following files do not have a valid build summary validation template as the last step of the last job:" -ForegroundColor Red
    Write-Host "  Valid templates:" -ForegroundColor Red
    foreach ($path in $validBuildSummaryValidationTemplatePaths) {
        Write-Host "    - $path" -ForegroundColor Red
    }
    Write-Host ""
    foreach ($issue in $issues) {
        Write-Host "  $($issue.File)" -ForegroundColor Yellow
        Write-Host "    last template: $($issue.Actual)" -ForegroundColor White
    }
}

$color = if ($issues.Count -eq 0) { 'Green' } else { 'Red' }
Write-Host "Check Build Summary Validation: $($issues.Count) error(s)" -ForegroundColor $color

if ($issues.Count -gt 0) { exit 1 }
