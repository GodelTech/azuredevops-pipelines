$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$azureDevOpsPath = Join-Path $repoRoot '.azuredevops'

$files = Get-ChildItem -Path $azureDevOpsPath -Recurse -Filter '*.yml' |
    Where-Object { $_.FullName -notmatch '[/\\]testHelpers[/\\]' }

function Get-TriggerIncludePaths {
    param([string]$content)

    $lines = ($content -replace "`r`n", "`n") -split "`n"
    $inTrigger = $false
    $inPaths = $false
    $inInclude = $false
    $paths = @()

    foreach ($line in $lines) {
        if ($line -match '^trigger:\s*$') {
            $inTrigger = $true
            continue
        }
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
                $inInclude = $false
            }
        }
    }

    return $paths
}

function Get-RepoRelativeTemplatePaths {
    param([string]$content, [string]$filePath, [string]$repoRoot)

    $fileDir = [System.IO.Path]::GetDirectoryName($filePath)
    $templatePaths = @()

    $templateMatches = [regex]::Matches($content, "template:\s+'([^']+)'|template:\s+`"([^`"]+)`"|template:\s+(\S+)")
    foreach ($m in $templateMatches) {
        $ref = if ($m.Groups[1].Success) { $m.Groups[1].Value }
               elseif ($m.Groups[2].Success) { $m.Groups[2].Value }
               else { $m.Groups[3].Value }

        $absolute = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($fileDir, $ref))
        $relative = $absolute.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $templatePaths += $relative
    }

    return $templatePaths | Select-Object -Unique
}

$issues = [ordered]@{}

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    $fileIssues = @()

    $selfPath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'

    if ($content -match '(?m)^trigger:\s*none\s*$') {
        $fileIssues += "trigger is 'none' - a paths-based trigger is required"
    } else {
        $triggerPaths = Get-TriggerIncludePaths -content $content

        if ($triggerPaths.Count -eq 0) {
            $fileIssues += "trigger.paths.include is missing or empty"
        } else {
            if ($selfPath -notin $triggerPaths) {
                $fileIssues += "trigger.paths.include missing self: '$selfPath'"
            }

            $templatePaths = Get-RepoRelativeTemplatePaths -content $content -filePath $file.FullName -repoRoot $repoRoot
            foreach ($templatePath in $templatePaths) {
                if ($templatePath -notin $triggerPaths) {
                    $fileIssues += "trigger.paths.include missing template: '$templatePath'"
                }
            }
        }
    }

    if ($fileIssues.Count -gt 0) {
        $issues[$file.FullName] = $fileIssues
    }
}

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
