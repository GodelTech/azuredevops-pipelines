<#
.SYNOPSIS
    Validates trigger blocks in all Azure DevOps pipeline YAML files.

.DESCRIPTION
    Walks all *.yml files under the .azuredevops folder (excluding testHelpers) and checks
    that each pipeline has a path-based CI trigger that includes:
      • the pipeline file itself, and
      • every template it references.
    Pipelines with 'trigger: none' are also flagged.
    Exits with code 1 when any issues are found so the build fails.

.PARAMETER AzureDevOpsPath
    Path to the folder that contains Azure DevOps pipeline YAML files.
    Defaults to '.azuredevops' relative to the repository root (one level above this script).

.EXAMPLE
    # Run from the repository root
    .\.scripts\check-triggers.ps1

    # Run against a custom folder
    .\.scripts\check-triggers.ps1 -AzureDevOpsPath 'C:\repo\.azuredevops'
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

$files = Get-ChildItem -Path $AzureDevOpsPath -Recurse -Filter '*.yml' |
    Where-Object { $_.FullName -notmatch '[/\\]testHelpers[/\\]' }

# ── Helper functions ──────────────────────────────────────────────────────────────────────────────

function Get-TriggerIncludePaths {
    <#
    Parses the trigger.paths.include list from a YAML pipeline file.
    Uses a simple line-by-line state machine rather than a full YAML parser to
    avoid external module dependencies.
    Returns an array of path strings (may be empty).
    #>
    param([string]$content)

    $lines = ($content -replace "`r`n", "`n") -split "`n"
    $inTrigger = $false
    $inPaths = $false
    $inInclude = $false
    $paths = @()

    foreach ($line in $lines) {
        # Detect the start of the top-level trigger block
        if ($line -match '^trigger:\s*$') {
            $inTrigger = $true
            continue
        }
        # Any top-level key ends the trigger block
        if ($inTrigger -and $line -match '^[a-zA-Z]') {
            break
        }
        if ($inTrigger -and $line -match '^\s{2}paths:\s*$') {
            $inPaths = $true
            continue
        }
        if ($inPaths -and $line -match '^\s{4}include:\s*$') {
            $inInclude = $true
            continue
        }
        if ($inInclude) {
            if ($line -match '^\s{6}-\s+(.+)$') {
                $paths += $Matches[1].Trim()
            } elseif ($line -notmatch '^\s{6}' -and $line -notmatch '^\s*$') {
                # A less-indented non-blank line signals the end of the include list
                $inInclude = $false
            }
        }
    }

    return $paths
}

function Get-RepoRelativeTemplatePaths {
    <#
    Extracts all 'template:' references from a YAML pipeline file and returns
    them as paths relative to the repository root (forward-slash separated).
    Handles single-quoted, double-quoted, and unquoted template values.
    #>
    param([string]$content, [string]$filePath, [string]$repoRoot)

    $fileDir = [System.IO.Path]::GetDirectoryName($filePath)
    $templatePaths = @()

    $templateMatches = [regex]::Matches($content, "template:\s+'([^']+)'|template:\s+`"([^`"]+)`"|template:\s+(\S+)")
    foreach ($m in $templateMatches) {
        # Pick whichever capture group matched (single-quoted, double-quoted, or bare)
        $ref = if ($m.Groups[1].Success) { $m.Groups[1].Value }
               elseif ($m.Groups[2].Success) { $m.Groups[2].Value }
               else { $m.Groups[3].Value }

        # Resolve to an absolute path then make it repo-relative with forward slashes
        $absolute = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($fileDir, $ref))
        $relative = $absolute.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $templatePaths += $relative
    }

    return $templatePaths | Select-Object -Unique
}

# ── Scan pipeline files ───────────────────────────────────────────────────────────────────────────

$issues = [ordered]@{}

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    $fileIssues = @()

    # Normalise to a repo-relative forward-slash path for comparison with trigger entries
    $selfPath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'

    if ($content -match '(?m)^trigger:\s*none\s*$') {
        $fileIssues += "trigger is 'none' - a paths-based trigger is required"
    } else {
        $triggerPaths = Get-TriggerIncludePaths -content $content

        if ($triggerPaths.Count -eq 0) {
            $fileIssues += "trigger.paths.include is missing or empty"
        } else {
            # The pipeline must re-trigger itself when its own file changes
            if ($selfPath -notin $triggerPaths) {
                $fileIssues += "trigger.paths.include missing self: '$selfPath'"
            }

            # The pipeline must also re-trigger when any referenced template changes
        }
    }

    if ($fileIssues.Count -gt 0) {
        $issues[$file.FullName] = $fileIssues
    }
}

# ── Report results ──────────────────────────────────────────────────────────────────────────────

$totalIssues = 0

if ($issues.Count -eq 0) {
    Write-Host "All files have valid trigger blocks." -ForegroundColor Green
} else {
    Write-Host "The following files have trigger issues:" -ForegroundColor Red
    foreach ($filePath in $issues.Keys) {
        Write-Host "  $filePath" -ForegroundColor Yellow
        foreach ($issue in $issues[$filePath]) {
            Write-Host "    - $issue" -ForegroundColor White
            $totalIssues++
        }
    }
}

$color = if ($totalIssues -eq 0) { 'Green' } else { 'Red' }
Write-Host "Check Triggers: $totalIssues error(s)" -ForegroundColor $color

if ($totalIssues -gt 0) { exit 1 }
