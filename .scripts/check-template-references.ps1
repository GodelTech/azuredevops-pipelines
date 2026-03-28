<#
.SYNOPSIS
    Validates that every local template reference in Azure DevOps pipeline YAML files resolves to an existing file.

.DESCRIPTION
    Walks all *.yml files under the repository root and, for each 'template:' line found,
    resolves the path relative to the file that contains it and checks that the target file
    exists on disk.
    Cross-repository references (those containing '@') are intentionally skipped because
    they cannot be validated locally.
    Exits with code 1 when any broken references are found so the build fails.

.PARAMETER RootPath
    Root path to search for YAML files.
    Defaults to the repository root (one level above this script).

.EXAMPLE
    # Run from the repository root
    .\.scripts\check-template-references.ps1

    # Run against a custom folder
    .\.scripts\check-template-references.ps1 -RootPath 'C:\repo'
#>
param(
    [string]$RootPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Resolve paths ─────────────────────────────────────────────────────────────────────────────
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if ($RootPath -eq '') {
    $RootPath = $repoRoot
}

$RootPath = [System.IO.Path]::GetFullPath($RootPath)

# ── Discover YAML files ───────────────────────────────────────────────────────────────────────
$yamlFiles = Get-ChildItem -Path $RootPath -Recurse -Filter '*.yml'

# ── Check each file ───────────────────────────────────────────────────────────────────────────
$issues = @()

foreach ($yamlFile in $yamlFiles) {
    $content = Get-Content -Path $yamlFile.FullName -Raw
    $fileDir  = [System.IO.Path]::GetDirectoryName($yamlFile.FullName)

    foreach ($match in [regex]::Matches($content, "(?m)^\s*-?\s*template:\s*['\`"]?([^'`"#\r\n]+)['\`"]?")) {
        $ref = $match.Groups[1].Value.Trim()

        # Skip cross-repository references (e.g. 'template.yml@myRepo')
        if ($ref -match '@') {
            continue
        }

        if ($ref -eq '') {
            continue
        }

        $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $fileDir $ref))

        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            $relativeSource = $yamlFile.FullName.Substring($RootPath.Length).TrimStart('\', '/')
            $issues += [pscustomobject]@{
                SourceFile     = $relativeSource
                TemplateRef    = $ref
                ResolvedPath   = $resolvedPath
            }
        }
    }
}

# ── Report results ────────────────────────────────────────────────────────────────────────────
if ($issues.Count -eq 0) {
    Write-Host 'All template references resolve to existing files.' -ForegroundColor Green
} else {
    Write-Host 'The following template references are broken:' -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  $($issue.SourceFile)" -ForegroundColor Yellow
        Write-Host "    Reference    : $($issue.TemplateRef)"
        Write-Host "    Resolved path: $($issue.ResolvedPath)"
    }
}

$color = if ($issues.Count -eq 0) { 'Green' } else { 'Red' }
Write-Host "Check Template References: $($issues.Count) error(s)" -ForegroundColor $color

if ($issues.Count -gt 0) { exit 1 }
