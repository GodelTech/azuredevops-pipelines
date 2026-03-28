<#
.SYNOPSIS
    Validates that every pipeline template has a corresponding test file in .azuredevops/test/.

.DESCRIPTION
    Walks all *.yml files outside the .azuredevops folder and checks for each template that:
      • A mirrored test file exists under .azuredevops/test/ at the same relative path, AND
      • That test file contains at least one 'template:' reference that resolves to the template.
    Exits with code 1 when any templates are not fully covered so the build fails.

.PARAMETER TemplatesPath
    Root path to search for template YAML files.
    Defaults to the repository root (one level above this script).

.PARAMETER TestPath
    Path to the folder that contains test pipeline YAML files.
    Defaults to '.azuredevops/test' relative to the repository root.

.EXAMPLE
    # Run from the repository root
    .\.scripts\check-test-coverage.ps1

    # Run against custom folders
    .\.scripts\check-test-coverage.ps1 -TemplatesPath 'C:\repo' -TestPath 'C:\repo\.azuredevops\test'
#>
param(
    [string]$TemplatesPath = '',
    [string]$TestPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Resolve paths ─────────────────────────────────────────────────────────────────────────────
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if ($TemplatesPath -eq '') {
    $TemplatesPath = $repoRoot
}

if ($TestPath -eq '') {
    $TestPath = Join-Path $repoRoot '.azuredevops\test'
}

$TemplatesPath = [System.IO.Path]::GetFullPath($TemplatesPath)
$TestPath      = [System.IO.Path]::GetFullPath($TestPath)

# ── Discover templates ────────────────────────────────────────────────────────────────────────
$templates = Get-ChildItem -Path $TemplatesPath -Recurse -Filter '*.yml' |
    Where-Object { $_.FullName -notmatch '[/\\]\.azuredevops[/\\]' }

# ── Helper: resolve template references from a test file ──────────────────────────────────────
function Get-TemplateReferences {
    <#
    .SYNOPSIS
        Parses all 'template:' lines from a YAML file and returns the resolved absolute paths.
    .DESCRIPTION
        Paths are resolved relative to the directory containing the test file.
    .PARAMETER FilePath
        Absolute path to the YAML test file, used to resolve relative template references.
    .PARAMETER Content
        Raw text content of the YAML test file.
    .OUTPUTS
        [string[]] Absolute paths of every referenced template.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Content
    )

    $dir  = [System.IO.Path]::GetDirectoryName($FilePath)
    $refs = @()

    foreach ($match in [regex]::Matches($Content, "template:\s*['\`"]?([^'`"#\r\n]+)['\`"]?")) {
        $ref = $match.Groups[1].Value.Trim()
        if ($ref -ne '') {
            $resolved = [System.IO.Path]::GetFullPath((Join-Path $dir $ref))
            $refs += $resolved
        }
    }

    return $refs
}

# ── Check each template ───────────────────────────────────────────────────────────────────────
$issues = @()

foreach ($template in $templates) {
    $relativePath = $template.FullName.Substring($TemplatesPath.Length).TrimStart('\', '/')
    $testFileRelative = $relativePath -replace '\.yml$', '.test.yml'
    $expectedTestFile = Join-Path $TestPath $testFileRelative

    # Check A: mirrored test file must exist
    if (-not (Test-Path $expectedTestFile)) {
        $issues += [pscustomobject]@{
            Template = $relativePath
            Reason   = 'no test file'
            TestFile = $expectedTestFile
        }
        continue
    }

    # Check B: test file must reference the template
    $testContent = Get-Content -Path $expectedTestFile -Raw
    $refs        = Get-TemplateReferences -FilePath $expectedTestFile -Content $testContent
    $templateAbs = [System.IO.Path]::GetFullPath($template.FullName)

    $found = $refs | Where-Object { $_ -eq $templateAbs }

    if (-not $found) {
        $issues += [pscustomobject]@{
            Template = $relativePath
            Reason   = 'not referenced in test file'
            TestFile = $expectedTestFile
        }
    }
}

# ── Report results ────────────────────────────────────────────────────────────────────────────
if ($issues.Count -eq 0) {
    Write-Host 'All templates are covered by test files.' -ForegroundColor Green
} else {
    Write-Host 'The following templates are not covered:' -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  $($issue.Template)" -ForegroundColor Yellow
        Write-Host "    Reason   : $($issue.Reason)"
        Write-Host "    Test file: $($issue.TestFile)"
    }
}

$color = if ($issues.Count -eq 0) { 'Green' } else { 'Red' }
Write-Host "Check Test Coverage: $($issues.Count) error(s)" -ForegroundColor $color

if ($issues.Count -gt 0) { exit 1 }
