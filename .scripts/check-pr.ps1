<#
.SYNOPSIS
    Validates pr blocks in all Azure DevOps pipeline YAML files.

.DESCRIPTION
    Walks all *.yml files under the .azuredevops folder (excluding testHelpers) and checks
    that each pipeline has a path-based PR trigger that includes:
      * the pipeline file itself, and
      * every template it references.
    It also checks that 'pr.branches.include' contains '*'.
    Pipelines with 'pr: none' are also flagged.
    Exits with code 1 when any issues are found so the build fails.

.PARAMETER AzureDevOpsPath
    Path to the folder that contains Azure DevOps pipeline YAML files.
    Defaults to '.azuredevops' relative to the repository root (one level above this script).

.EXAMPLE
    # Run from the repository root
    .\.scripts\check-pr.ps1

    # Run against a custom folder
    .\.scripts\check-pr.ps1 -AzureDevOpsPath 'C:\repo\.azuredevops'
#>
param(
    [string]$AzureDevOpsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Resolve paths -----------------------------------------------------------------------------
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if ($AzureDevOpsPath -eq '') {
    $AzureDevOpsPath = Join-Path $repoRoot '.azuredevops'
}

$files = Get-ChildItem -Path $AzureDevOpsPath -Recurse -Filter '*.yml' |
    Where-Object { $_.FullName -notmatch '[/\\]testHelpers[/\\]' }

# -- Helper functions ------------------------------------------------------------------------------

function Get-PrBranchesInclude {
    <#
    .SYNOPSIS
        Parses the pr.branches.include list from a YAML pipeline file.
    .DESCRIPTION
        Uses a simple line-by-line state machine rather than a full YAML parser to
        avoid external module dependencies.
    .PARAMETER Content
        Raw text content of the YAML pipeline file.
    .OUTPUTS
        [string[]] Array of branch strings; may be empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $lines = ($Content -replace "`r`n", "`n") -split "`n"
    $inPr = $false
    $inBranches = $false
    $inInclude = $false
    $branches = @()

    foreach ($line in $lines) {
        # Detect the start of the top-level pr block
        if ($line -match '^pr:\s*$') {
            $inPr = $true
            continue
        }
        # Any top-level key ends the pr block
        if ($inPr -and $line -match '^[a-zA-Z]') {
            break
        }
        if ($inPr -and $line -match '^\s{2}branches:\s*$') {
            $inBranches = $true
            continue
        }
        if ($inBranches -and $line -match '^\s{4}include:\s*$') {
            $inInclude = $true
            continue
        }
        if ($inInclude) {
            if ($line -match '^\s{6}-\s+(.+)$') {
                $branches += $Matches[1].Trim().Trim("'").Trim('"')
            } elseif ($line -notmatch '^\s{6}' -and $line -notmatch '^\s*$') {
                $inInclude = $false
            }
        }
    }

    return $branches
}

function Get-PrIncludePaths {
    <#
    .SYNOPSIS
        Parses the pr.paths.include list from a YAML pipeline file.
    .DESCRIPTION
        Uses a simple line-by-line state machine rather than a full YAML parser to
        avoid external module dependencies.
    .PARAMETER Content
        Raw text content of the YAML pipeline file.
    .OUTPUTS
        [string[]] Array of include path strings; may be empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $lines = ($Content -replace "`r`n", "`n") -split "`n"
    $inPr = $false
    $inPaths = $false
    $inInclude = $false
    $paths = @()

    foreach ($line in $lines) {
        # Detect the start of the top-level pr block
        if ($line -match '^pr:\s*$') {
            $inPr = $true
            continue
        }
        # Any top-level key ends the pr block
        if ($inPr -and $line -match '^[a-zA-Z]') {
            break
        }
        if ($inPr -and $line -match '^\s{2}paths:\s*$') {
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
        # Pick whichever capture group matched (single-quoted, double-quoted, or bare)
        $ref = if ($m.Groups[1].Success) { $m.Groups[1].Value }
               elseif ($m.Groups[2].Success) { $m.Groups[2].Value }
               else { $m.Groups[3].Value }

        # Resolve to an absolute path then make it repo-relative with forward slashes
        $absolute = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($fileDir, $ref))
        $relative = $absolute.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $templatePaths += $relative
    }

    return $templatePaths | Select-Object -Unique
}

# -- Scan pipeline files ---------------------------------------------------------------------------

$issues = [ordered]@{}

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    $fileIssues = @()

    # Normalise to a repo-relative forward-slash path for comparison with pr entries
    $selfPath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'

    if ($content -match '(?m)^pr:\s*none\s*$') {
        $fileIssues += "pr is 'none' - a paths-based pr trigger is required"
    } elseif ($content -notmatch '(?m)^pr:\s*$') {
        $fileIssues += "pr block is missing"
    } else {
        $prBranches = @(Get-PrBranchesInclude -Content $content)
        if ($prBranches -notcontains '*') {
            $fileIssues += "pr.branches.include must contain '*'"
        }

        # CI.yml is exempt from paths checks as it intentionally uses a branch-only pr trigger
        if ($file.Name -ne 'CI.yml') {
            $prPaths = @(Get-PrIncludePaths -Content $content)

            if ($prPaths.Count -eq 0) {
                $fileIssues += "pr.paths.include is missing or empty"
            } else {
                # The pipeline must re-trigger itself when its own file changes
                if ($selfPath -notin $prPaths) {
                    $fileIssues += "pr.paths.include missing self: '$selfPath'"
                }

                # The pipeline must also re-trigger when any referenced template changes
                $templatePaths = @(Get-RepoRelativeTemplatePaths -Content $content -FilePath $file.FullName -RepoRoot $repoRoot)
                foreach ($templatePath in $templatePaths) {
                    $templateFullPath = Join-Path $repoRoot $templatePath
                    if (-not (Test-Path -Path $templateFullPath)) {
                        $fileIssues += "template file does not exist: '$templatePath'"
                        continue
                    }
                    if ($templatePath -notin $prPaths) {
                        $fileIssues += "pr.paths.include missing template: '$templatePath'"
                    }
                }

                # The pr trigger must not include paths that are not the pipeline itself or a referenced template
                # (glob patterns containing '*' are intentional wildcards and are exempt from this check)
                $allowedPaths = @($selfPath) + $templatePaths
                foreach ($prPath in $prPaths) {
                    if ($prPath -notlike '*`**' -and $prPath -notin $allowedPaths) {
                        $fileIssues += "pr.paths.include has unreferenced path: '$prPath'"
                    }
                }
            }
        }
    }

    if ($fileIssues.Count -gt 0) {
        $issues[$file.FullName] = $fileIssues
    }
}

# -- Report results ------------------------------------------------------------------------------

$totalIssues = 0

if ($issues.Count -eq 0) {
    Write-Host "All files have valid pr blocks." -ForegroundColor Green
} else {
    Write-Host "The following files have pr issues:" -ForegroundColor Red
    foreach ($filePath in $issues.Keys) {
        Write-Host "  $filePath" -ForegroundColor Yellow
        foreach ($issue in $issues[$filePath]) {
            Write-Host "    - $issue" -ForegroundColor White
            $totalIssues++
        }
    }
}

$color = if ($totalIssues -eq 0) { 'Green' } else { 'Red' }
Write-Host "Check PR: $totalIssues error(s)" -ForegroundColor $color

if ($totalIssues -gt 0) { exit 1 }
