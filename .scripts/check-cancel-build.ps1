<#
.SYNOPSIS
    Verifies that no Azure DevOps pipeline YAML file references the cancel-build template directly.

.DESCRIPTION
    Walks all *.yml files under the .azuredevops folder (excluding testHelpers) and checks
    that none of them contain a template reference that resolves to
    'azuredevops/build/cancel-build.yml'.
    Exits with code 1 if any files reference the template so the build fails.

.PARAMETER AzureDevOpsPath
    Path to the folder that contains Azure DevOps pipeline YAML files.
    Defaults to '.azuredevops' relative to the repository root (one level above this script).

.PARAMETER ExcludeFiles
    List of repo-root-relative paths (forward-slash separated) to exclude from the check.
    Use this for files that are permitted to reference the cancel-build template directly.

.EXAMPLE
    # Run from the repository root
    .\.scripts\check-cancel-build.ps1

    # Run against a custom folder
    .\.scripts\check-cancel-build.ps1 -AzureDevOpsPath 'C:\repo\.azuredevops'
#>
param(
    [string]$AzureDevOpsPath = '',
    [string[]]$ExcludeFiles   = @(
        '.azuredevops/test/azuredevops/build/cancel-build.test.yml'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Resolve paths ─────────────────────────────────────────────────────────────────────────────
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if ($AzureDevOpsPath -eq '') {
    $AzureDevOpsPath = Join-Path $repoRoot '.azuredevops'
}

# The canonical repo-relative path every pipeline must reference
$cancelBuildTemplatePath = 'azuredevops/build/cancel-build.yml'

# ── Helper ────────────────────────────────────────────────────────────────────────────────────

function Get-RepoRelativeTemplatePaths {
    <#
    .SYNOPSIS
        Extracts all 'template:' references from a YAML pipeline file.
    .DESCRIPTION
        Returns all template paths as paths relative to the repository root (forward-slash
        separated). Handles single-quoted, double-quoted, and unquoted template values.
    .PARAMETER Content
        Raw text content of the YAML pipeline file.
    .PARAMETER FilePath
        Absolute path to the YAML pipeline file, used to resolve relative template references.
    .PARAMETER RepoRoot
        Absolute path to the repository root, used to compute repo-relative output paths.
    .OUTPUTS
        [string[]] Unique repo-relative forward-slash paths for every referenced template.
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
    $templatePaths = @()

    $templateMatches = [regex]::Matches($Content, "template:\s+'([^']+)'|template:\s+`"([^`"]+)`"|template:\s+(\S+)")
    foreach ($m in $templateMatches) {
        $ref = if ($m.Groups[1].Success) { $m.Groups[1].Value }
               elseif ($m.Groups[2].Success) { $m.Groups[2].Value }
               else { $m.Groups[3].Value }

        $absolute = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($fileDir, $ref))
        $relative = $absolute.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $templatePaths += $relative
    }

    return $templatePaths | Select-Object -Unique
}

# ── Scan pipeline files ───────────────────────────────────────────────────────────────────────────

$files = Get-ChildItem -Path $AzureDevOpsPath -Recurse -Filter '*.yml' |
    Where-Object { $_.FullName -notmatch '[/\\]testHelpers[/\\]' }

$found = @()

foreach ($file in $files) {
    $repoRelative = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    if ($repoRelative -in $ExcludeFiles) { continue }

    $content = Get-Content -Path $file.FullName -Raw
    $templatePaths = Get-RepoRelativeTemplatePaths -Content $content -FilePath $file.FullName -RepoRoot $repoRoot

    if ($cancelBuildTemplatePath -in $templatePaths) {
        $found += $file.FullName
    }
}

# ── Report results ──────────────────────────────────────────────────────────────────────────────

if ($found.Count -eq 0) {
    Write-Host "No files reference '$cancelBuildTemplatePath' template directly." -ForegroundColor Green
} else {
    Write-Host "The following files must not reference '$cancelBuildTemplatePath' directly:" -ForegroundColor Red
    $found | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

$color = if ($found.Count -eq 0) { 'Green' } else { 'Red' }
Write-Host "Check Cancel Build: $($found.Count) error(s)" -ForegroundColor $color

if ($found.Count -gt 0) { exit 1 }
