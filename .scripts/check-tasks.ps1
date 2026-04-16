<#
.SYNOPSIS
    Checks whether marketplace task references in Azure DevOps pipeline YAML files use the latest extension version.

.DESCRIPTION
    Walks all *.yml files under the repository root and, for each 'task:' line that references
    a marketplace extension, queries the Visual Studio Marketplace API for the latest version.
    Supports two task reference formats:
      - Full-qualified: publisher.extension.contribution@version (auto-detected)
      - Short-name: TaskName@version (looked up via a configurable mapping)
    Built-in tasks (e.g. DotNetCoreCLI@2) are checked for newer major versions by probing
    Microsoft documentation pages at learn.microsoft.com.
    Exits with code 1 when any outdated task references are found.

.PARAMETER RootPath
    Root path to search for YAML files.
    Defaults to the repository root (one level above this script).

.EXAMPLE
    # Run from the repository root
    .\.scripts\check-tasks.ps1

    # Run against a custom folder
    .\.scripts\check-tasks.ps1 -RootPath 'C:\repo'
#>
[CmdletBinding()]
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

if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
    Write-Error "RootPath does not exist: $RootPath"
    exit 1
}

# ── Known built-in tasks ──────────────────────────────────────────────────────────────────────
# Azure DevOps agent built-in tasks. These ship with the agent and have no
# marketplace extension. Each entry maps the task name to its Microsoft docs URL slug
# (used to probe for newer major versions at learn.microsoft.com).
# Add entries here when new built-in tasks are used in the repository.
$builtInTasks = @{
    'Cache'                      = 'cache'
    'CmdLine'                    = 'cmd-line'
    'DotNetCoreCLI'              = 'dotnet-core-cli'
    'DownloadBuildArtifacts'     = 'download-build-artifacts'
    'DownloadPipelineArtifact'   = 'download-pipeline-artifact'
    'NuGetAuthenticate'          = 'nuget-authenticate'
    'NuGetCommand'               = 'nuget-command'
    'NuGetToolInstaller'         = 'nuget-tool-installer'
    'PowerShell'                 = 'powershell'
    'PublishBuildArtifacts'      = 'publish-build-artifacts'
    'PublishCodeCoverageResults' = 'publish-code-coverage-results'
    'PublishPipelineArtifact'    = 'publish-pipeline-artifact'
    'PublishTestResults'         = 'publish-test-results'
    'UseDotNet'                  = 'use-dotnet'
    'UseNode'                    = 'use-node'
    'UsePythonVersion'           = 'use-python-version'
    'VSBuild'                    = 'vsbuild'
    'VSTest'                     = 'vstest'
}

# ── Short-name marketplace task mapping ───────────────────────────────────────────────────────
# Maps short task names (case-insensitive) to their marketplace extension IDs.
# Add entries here when new marketplace tasks are used in the repository.
$shortNameMapping = @{
    'BuildQualityChecks'      = @{ ExtensionId = 'mspremier.BuildQualityChecks';              LastChecked = [datetime]'2026-04-15' }
    'PublishMutationReport'   = @{ ExtensionId = 'stryker-mutator.mutation-report-publisher'; LastChecked = [datetime]'2026-04-15' }
    'SonarCloudPrepare'       = @{ ExtensionId = 'SonarSource.sonarcloud';                    LastChecked = [datetime]'2026-04-15' }
    'SonarCloudAnalyze'       = @{ ExtensionId = 'SonarSource.sonarcloud';                    LastChecked = [datetime]'2026-04-15' }
    'SonarCloudPublish'       = @{ ExtensionId = 'SonarSource.sonarcloud';                    LastChecked = [datetime]'2026-04-15' }
    'sonarcloud-buildbreaker' = @{ ExtensionId = 'SimondeLang.sonarcloud-buildbreaker';       LastChecked = [datetime]'2026-04-15' }
}

# ── Constants ─────────────────────────────────────────────────────────────────────────────────
Set-Variable -Name 'docsBaseUrl' -Value 'https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference' -Option ReadOnly
Set-Variable -Name 'maxVersionProbeRange' -Value 10 -Option ReadOnly

# ── Helper functions ──────────────────────────────────────────────────────────────────────────

function Get-MarketplaceExtensionVersion {
    <#
    .SYNOPSIS
        Queries the Visual Studio Marketplace API for the latest version of an extension.

    .PARAMETER PublisherName
        The publisher identifier (e.g. 'gittools').

    .PARAMETER ExtensionName
        The extension identifier (e.g. 'gittools').

    .OUTPUTS
        [pscustomobject] with Version and LastUpdated properties, or $null if the extension was not found.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$PublisherName,

        [Parameter(Mandatory)]
        [string]$ExtensionName
    )

    $body = @{
        filters = @(
            @{
                criteria = @(
                    @{
                        filterType = 7
                        value      = "$PublisherName.$ExtensionName"
                    }
                )
            }
        )
        flags   = 0x200
    } | ConvertTo-Json -Depth 5

    $restParams = @{
        Uri         = 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery?api-version=7.1-preview.1'
        Method      = 'Post'
        ContentType = 'application/json'
        Body        = $body
        TimeoutSec  = 30
    }

    try {
        $response = Invoke-RestMethod @restParams
    } catch {
        Write-Warning "Failed to query marketplace for '${PublisherName}.${ExtensionName}': $_"
        return $null
    }

    $extension = $response.results[0].extensions
    if ($null -eq $extension -or $extension.Count -eq 0) {
        return $null
    }

    $ext = $extension[0]
    $lastUpdated = if ($ext.PSObject.Properties['lastUpdated']) {
        ([datetime]$ext.lastUpdated).ToString('yyyy-MM-dd')
    } else {
        $null
    }

    return [pscustomobject]@{
        Version     = $ext.versions[0].version
        LastUpdated = $lastUpdated
    }
}

function Get-BuiltInTaskLatestVersion {
    <#
    .SYNOPSIS
        Probes Microsoft documentation pages to find the latest major version of a built-in task.

    .PARAMETER CurrentVersion
        The major version currently referenced in YAML (e.g. 2 for DotNetCoreCLI@2).

    .PARAMETER DocsSlug
        The URL slug for the task on learn.microsoft.com (e.g. 'dotnet-core-cli').

    .PARAMETER DocsBaseUrl
        Base URL for the Microsoft docs task reference pages.

    .OUTPUTS
        [pscustomobject] with LatestVersion (int), LastUpdated (string or $null), SlugValid (bool), and CurrentPageFound (bool).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [int]$CurrentVersion,

        [Parameter(Mandatory)]
        [string]$DocsSlug,

        [Parameter(Mandatory)]
        [string]$DocsBaseUrl
    )

    $latestVersion = $CurrentVersion
    $lastUpdated = $null
    $currentPageFound = $true

    # Fetch the current version page to get last updated date
    $currentUrl = "${DocsBaseUrl}/${DocsSlug}-v${CurrentVersion}?view=azure-pipelines"
    $webParams = @{
        Uri             = $currentUrl
        UseBasicParsing = $true
        TimeoutSec      = 15
        ErrorAction     = 'Stop'
    }
    try {
        $page = Invoke-WebRequest @webParams
        if ($page.Content -match 'Last updated on[\s\S]*?datetime="(\d{4}-\d{2}-\d{2})') {
            $lastUpdated = $Matches[1]
        }
    } catch {
        $currentPageFound = $false
    }

    # Probe for newer major versions
    for ($v = $CurrentVersion + 1; $v -le $CurrentVersion + $maxVersionProbeRange; $v++) {
        $url = "${DocsBaseUrl}/${DocsSlug}-v${v}?view=azure-pipelines"
        $headParams = @{
            Uri             = $url
            Method          = 'Head'
            UseBasicParsing = $true
            TimeoutSec      = 15
            ErrorAction     = 'Stop'
        }
        try {
            $null = Invoke-WebRequest @headParams
            $latestVersion = $v
        } catch {
            # Expected — page does not exist, stop probing
            break
        }
    }

    # If the current version page was not found, validate the slug by probing other versions
    $slugValid = $currentPageFound -or ($latestVersion -gt $CurrentVersion)
    if (-not $currentPageFound -and -not $slugValid) {
        # Probe lower versions to confirm whether the slug exists at all
        for ($v = [Math]::Max(0, $CurrentVersion - 1); $v -ge 0; $v--) {
            $url = "${DocsBaseUrl}/${DocsSlug}-v${v}?view=azure-pipelines"
            $headParams = @{
                Uri             = $url
                Method          = 'Head'
                UseBasicParsing = $true
                TimeoutSec      = 15
                ErrorAction     = 'Stop'
            }
            try {
                $null = Invoke-WebRequest @headParams
                $slugValid = $true
                # The current version does not exist and no higher version was found,
                # so the highest real version is this lower one.
                $latestVersion = $v
                break
            } catch {
                # Continue probing
            }
        }
    }

    return [pscustomobject]@{
        LatestVersion    = $latestVersion
        LastUpdated      = $lastUpdated
        SlugValid        = $slugValid
        CurrentPageFound = $currentPageFound
    }
}

function Resolve-TaskReference {
    <#
    .SYNOPSIS
        Resolves a task reference string into its components.

    .PARAMETER TaskString
        The full task string (e.g. 'gittools.gittools.setup-gitversion-task.gitversion-setup@4.3.3',
        'BuildQualityChecks@10', or 'PowerShell@2').

    .PARAMETER BuiltInTasks
        Hashtable of known built-in task names (keys) mapped to docs URL slugs (values).

    .PARAMETER ShortNameMapping
        Hashtable mapping short task names to marketplace extension IDs.

    .OUTPUTS
        [pscustomobject] with Source ('Marketplace', 'Built-in', or 'Unknown'), ExtensionId, TaskName, CurrentVersion, and IsShortName.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$TaskString,

        [Parameter(Mandatory)]
        [hashtable]$BuiltInTasks,

        [Parameter(Mandatory)]
        [hashtable]$ShortNameMapping
    )

    # Must have name@version format
    if ($TaskString -notmatch '^([^@]+)@(.+)$') {
        return $null
    }

    $taskName = $Matches[1]
    $version = $Matches[2]

    $segments = $taskName -split '\.'
    if ($segments.Count -ge 3) {
        # Full-qualified marketplace reference: publisher.extension.contribution@version
        return [pscustomobject]@{
            Source         = 'Marketplace'
            ExtensionId    = "$($segments[0]).$($segments[1])"
            TaskName       = $taskName
            CurrentVersion = $version
            IsShortName    = $false
        }
    }

    # Short-name reference: check marketplace mapping
    if ($ShortNameMapping.ContainsKey($taskName)) {
        $mapping = $ShortNameMapping[$taskName]
        return [pscustomobject]@{
            Source         = 'Marketplace'
            ExtensionId    = $mapping.ExtensionId
            TaskName       = $taskName
            CurrentVersion = $version
            IsShortName    = $true
        }
    }

    # Check built-in tasks list
    if ($BuiltInTasks.ContainsKey($taskName)) {
        return [pscustomobject]@{
            Source         = 'Built-in'
            ExtensionId    = ''
            TaskName       = $taskName
            CurrentVersion = $version
            IsShortName    = $true
        }
    }

    # Unclassified task — not in either list
    return [pscustomobject]@{
        Source         = 'Unknown'
        ExtensionId    = ''
        TaskName       = $taskName
        CurrentVersion = $version
        IsShortName    = $true
    }
}

# ── Discover YAML files ───────────────────────────────────────────────────────────────────────
$yamlFiles = @(Get-ChildItem -Path $RootPath -Recurse -Filter '*.yml' |
    Where-Object { $_.FullName -notmatch '[\\/]node_modules[\\/]' })

# ── Extract task references ───────────────────────────────────────────────────────────────────
$taskReferences = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($yamlFile in $yamlFiles) {
    $content = Get-Content -Path $yamlFile.FullName -Raw
    $relativeFile = $yamlFile.FullName.Substring($RootPath.Length).TrimStart('\', '/') -replace '\\', '/'

    foreach ($match in [regex]::Matches($content, '(?m)^\s*-?\s*task:\s*(\S+)')) {
        $taskString = $match.Groups[1].Value.Trim()
        $parsed = Resolve-TaskReference -TaskString $taskString -BuiltInTasks $builtInTasks -ShortNameMapping $shortNameMapping

        if ($null -ne $parsed) {
            $taskReferences.Add([pscustomobject]@{
                File           = $relativeFile
                TaskString     = $taskString
                Source         = $parsed.Source
                ExtensionId    = $parsed.ExtensionId
                TaskName       = $parsed.TaskName
                CurrentVersion = $parsed.CurrentVersion
                IsShortName    = $parsed.IsShortName
            })
        }
    }
}

if ($taskReferences.Count -eq 0) {
    Write-Host 'No task references found.' -ForegroundColor Green
    exit 0
}

# ── Display all discovered tasks ──────────────────────────────────────────────────────────────
$uniqueTasks = $taskReferences |
    Select-Object -Property TaskString, Source, ExtensionId -Unique |
    Sort-Object -Property Source, @{ Expression = { $_.TaskString.ToLower() } }

Write-Host ''
Write-Host 'Discovered tasks:' -ForegroundColor Cyan
foreach ($task in $uniqueTasks) {
    $sourceLabel = switch ($task.Source) {
        'Built-in'    { '[Built-in]   ' }
        'Marketplace' { '[Marketplace]' }
        'Unknown'     { '[Unknown]    ' }
    }
    $extensionInfo = if ($task.ExtensionId -ne '') { " ($($task.ExtensionId))" } else { '' }
    $color = if ($task.Source -eq 'Unknown') { 'Yellow' } else { 'White' }
    Write-Host "  $sourceLabel $($task.TaskString)$extensionInfo" -ForegroundColor $color
}
Write-Host ''

# ── Query marketplace for each unique extension ───────────────────────────────────────────────
$marketplaceRefs = $taskReferences | Where-Object { $_.Source -eq 'Marketplace' }
$extensionIds = @($marketplaceRefs | Select-Object -ExpandProperty ExtensionId -Unique)
$latestVersions = @{}
$marketplaceErrors = 0

foreach ($extensionId in $extensionIds) {
    $parts = $extensionId -split '\.', 2
    $publisherName = $parts[0]
    $extensionName = $parts[1]

    $taskNames = $marketplaceRefs |
        Where-Object { $_.ExtensionId -eq $extensionId } |
        Select-Object -ExpandProperty TaskString -Unique |
        Sort-Object

    Write-Host "Querying marketplace for '$extensionId'..." -ForegroundColor Cyan
    Write-Host "  URL: https://marketplace.visualstudio.com/items?itemName=$extensionId"
    $result = Get-MarketplaceExtensionVersion -PublisherName $publisherName -ExtensionName $extensionName

    if ($null -eq $result) {
        Write-Host "  Extension '$extensionId' not found on the marketplace." -ForegroundColor Red
        $marketplaceErrors++
    } else {
        $updatedInfo = if ($result.LastUpdated) { $result.LastUpdated } else { 'unknown' }
        Write-Host "  Latest version: $($result.Version)"
        Write-Host "  Last updated: $updatedInfo"
        $latestVersions[$extensionId] = $result
    }
    foreach ($name in $taskNames) {
        Write-Host "  Task: $name"
    }
}

# ── Compare versions ─────────────────────────────────────────────────────────────────────────
$issues = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($ref in $marketplaceRefs) {
    if (-not $latestVersions.ContainsKey($ref.ExtensionId)) {
        continue
    }

    $marketplaceResult = $latestVersions[$ref.ExtensionId]
    $latestVersion = $marketplaceResult.Version

    if ($ref.IsShortName) {
        # Short-name tasks use @MajorVersion (e.g. BuildQualityChecks@10).
        # Azure DevOps auto-resolves the latest minor/patch within the major.
        # The marketplace API only exposes the extension-level version, not
        # individual task major versions, so automated version comparison is
        # not possible. Check if the extension was updated since last manual review.
        if ($shortNameMapping.ContainsKey($ref.TaskName)) {
            $mapping = $shortNameMapping[$ref.TaskName]
            if ($mapping.LastChecked -and $marketplaceResult.LastUpdated) {
                if ([datetime]$marketplaceResult.LastUpdated -gt $mapping.LastChecked) {
                    $issues.Add([pscustomobject]@{
                        File           = $ref.File
                        Task           = $ref.TaskString
                        CurrentVersion = $ref.CurrentVersion
                        LatestVersion  = "updated $($marketplaceResult.LastUpdated)"
                        Link           = "https://marketplace.visualstudio.com/items?itemName=$($ref.ExtensionId)"
                        Reason         = 'needs-review'
                    })
                }
            }
        }
        continue
    }

    try {
        $currentVer = [version]$ref.CurrentVersion
        $latestVer = [version]$latestVersion

        # Normalize to 3-part versions (Major.Minor.Build) for comparison,
        # because the marketplace may return a 4-part build number that users
        # do not include in YAML task references.
        $currentNormalized = [version]::new($currentVer.Major, $currentVer.Minor, [Math]::Max($currentVer.Build, 0))
        $latestNormalized = [version]::new($latestVer.Major, $latestVer.Minor, [Math]::Max($latestVer.Build, 0))

        if ($currentNormalized -lt $latestNormalized) {
            $issues.Add([pscustomobject]@{
                File           = $ref.File
                Task           = $ref.TaskString
                CurrentVersion = $ref.CurrentVersion
                LatestVersion  = "$($latestNormalized.Major).$($latestNormalized.Minor).$($latestNormalized.Build)"
                Link           = "https://marketplace.visualstudio.com/items?itemName=$($ref.ExtensionId)"
                Reason         = 'outdated'
            })
        }
    } catch {
        Write-Warning "Could not parse version '$($ref.CurrentVersion)' or '$latestVersion' for task '$($ref.TaskString)' - falling back to string comparison."
        if ($ref.CurrentVersion -ne $latestVersion) {
            $issues.Add([pscustomobject]@{
                File           = $ref.File
                Task           = $ref.TaskString
                CurrentVersion = $ref.CurrentVersion
                LatestVersion  = $latestVersion
                Link           = "https://marketplace.visualstudio.com/items?itemName=$($ref.ExtensionId)"
                Reason         = 'outdated'
            })
        }
    }
}

# ── Query docs for built-in task versions ────────────────────────────────────────────────────
$builtInRefs = $taskReferences | Where-Object { $_.Source -eq 'Built-in' }
$builtInUniqueVersions = @($builtInRefs |
    Select-Object -Property TaskName, CurrentVersion -Unique)

$slugErrors = 0

foreach ($ref in $builtInUniqueVersions) {
    $slug = $builtInTasks[$ref.TaskName]
    if (-not $slug) { continue }

    $currentVersionInt = $null
    if (-not [int]::TryParse($ref.CurrentVersion, [ref]$currentVersionInt)) {
        Write-Warning "Non-integer version '$($ref.CurrentVersion)' for built-in task '$($ref.TaskName)' - skipping docs check."
        continue
    }

    Write-Host "Checking docs for '$($ref.TaskName)@$($ref.CurrentVersion)'..." -ForegroundColor Cyan
    Write-Host "  URL: ${docsBaseUrl}/${slug}-v${currentVersionInt}?view=azure-pipelines"
    $result = Get-BuiltInTaskLatestVersion -CurrentVersion $currentVersionInt -DocsSlug $slug -DocsBaseUrl $docsBaseUrl

    if (-not $result.SlugValid) {
        $expectedUrl = "${docsBaseUrl}/${slug}-v$($ref.CurrentVersion)?view=azure-pipelines"
        Write-Host "  Docs page not found: $expectedUrl" -ForegroundColor Red
        Write-Host "  The slug '$slug' for '$($ref.TaskName)' may be incorrect in `$builtInTasks." -ForegroundColor Red
        Write-Host "  Find the correct slug at: https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference" -ForegroundColor Cyan
        $slugErrors++
        continue
    }

    if (-not $result.CurrentPageFound) {
        Write-Host "  No docs page for version $($ref.CurrentVersion), but slug is valid" -ForegroundColor Yellow
    }

    $latestMajor = $result.LatestVersion
    $updatedInfo = if ($result.LastUpdated) { $result.LastUpdated } else { 'unknown' }

    if ($latestMajor -ne $currentVersionInt) {
        if ($latestMajor -lt $currentVersionInt) {
            Write-Host "  Version $($ref.CurrentVersion) does not exist. Latest version: $latestMajor" -ForegroundColor Red
        } elseif (-not $result.CurrentPageFound) {
            Write-Host "  Version $($ref.CurrentVersion) does not exist. Latest version: $latestMajor" -ForegroundColor Red
        } else {
            Write-Host "  Newer version available: $latestMajor" -ForegroundColor Yellow
            Write-Host "  Last updated: $updatedInfo" -ForegroundColor Yellow
        }
        $reason = if (-not $result.CurrentPageFound -or $latestMajor -lt $currentVersionInt) { 'non-existent' } else { 'outdated' }
        $outdatedBuiltInRefs = $builtInRefs |
            Where-Object { $_.TaskName -eq $ref.TaskName -and $_.CurrentVersion -eq $ref.CurrentVersion }
        foreach ($outdatedRef in $outdatedBuiltInRefs) {
            $issues.Add([pscustomobject]@{
                File           = $outdatedRef.File
                Task           = $outdatedRef.TaskString
                CurrentVersion = $outdatedRef.CurrentVersion
                LatestVersion  = $latestMajor.ToString()
                Link           = "${docsBaseUrl}/${slug}-v${latestMajor}?view=azure-pipelines"
                Reason         = $reason
            })
        }
    } else {
        Write-Host "  Up to date"
        Write-Host "  Last updated: $updatedInfo"
    }
}

# ── Check for unclassified tasks ──────────────────────────────────────────────────────────────
$unknownTasks = @($taskReferences |
    Where-Object { $_.Source -eq 'Unknown' } |
    Select-Object -Property TaskString, File -Unique)

if ($unknownTasks.Count -gt 0) {
    Write-Host ''
    Write-Host 'The following tasks are not classified as built-in or marketplace:' -ForegroundColor Red
    foreach ($unknown in $unknownTasks) {
        Write-Host "  $($unknown.File)" -ForegroundColor Yellow
        Write-Host "    Task: $($unknown.TaskString)"
    }
    Write-Host ''
    Write-Host 'Add each task to either $builtInTasks or $shortNameMapping in:' -ForegroundColor Cyan
    Write-Host "  .scripts/check-tasks.ps1" -ForegroundColor Cyan
}

# ── Check for multiple versions of the same task ─────────────────────────────────────────────
$multiVersionTasks = @($taskReferences |
    Where-Object { $_.IsShortName } |
    Group-Object -Property TaskName |
    Where-Object {
        @($_.Group | Select-Object -ExpandProperty CurrentVersion -Unique).Count -gt 1
    })

if ($multiVersionTasks.Count -gt 0) {
    Write-Host ''
    Write-Host 'The following tasks are used with multiple major versions:' -ForegroundColor Red
    foreach ($group in $multiVersionTasks) {
        $versions = ($group.Group | Select-Object -ExpandProperty CurrentVersion -Unique | Sort-Object) -join ', '
        Write-Host "  $($group.Name) @ $versions" -ForegroundColor Yellow
        $group.Group |
            Select-Object -Property File, TaskString -Unique |
            ForEach-Object { Write-Host "    $($_.File)  ($($_.TaskString))" }
    }
    Write-Host ''
    Write-Host 'Consolidate each task to a single version.' -ForegroundColor Cyan
}

# ── Helper: write task issue details ──────────────────────────────────────────────────────────

function Write-TaskIssue {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]]$Issues,

        [Parameter()]
        [string]$VersionSuffix = ''
    )

    foreach ($issue in $Issues) {
        Write-Host "  $($issue.File)" -ForegroundColor Yellow
        Write-Host "    Task           : $($issue.Task)"
        Write-Host "    Current version: $($issue.CurrentVersion)$VersionSuffix"
        Write-Host "    Latest version : $($issue.LatestVersion)"
        Write-Host "    Reference      : $($issue.Link)"
    }
}

# ── Report results ────────────────────────────────────────────────────────────────────────────
$uniqueIssues = @($issues | Select-Object -Property File, Task, CurrentVersion, LatestVersion, Link, Reason -Unique)
$outdatedIssues = @($uniqueIssues | Where-Object { $_.Reason -eq 'outdated' })
$nonExistentIssues = @($uniqueIssues | Where-Object { $_.Reason -eq 'non-existent' })
$totalErrors = $outdatedIssues.Count + $nonExistentIssues.Count + $unknownTasks.Count + $multiVersionTasks.Count + $slugErrors + $marketplaceErrors

if ($totalErrors -eq 0) {
    Write-Host 'All task references are up to date.' -ForegroundColor Green
} elseif ($uniqueIssues.Count -gt 0) {
    if ($outdatedIssues.Count -gt 0) {
        Write-Host 'The following task references are outdated:' -ForegroundColor Red
        Write-TaskIssue -Issues $outdatedIssues
    }

    if ($nonExistentIssues.Count -gt 0) {
        Write-Host 'The following task references use a version that does not exist:' -ForegroundColor Red
        Write-TaskIssue -Issues $nonExistentIssues -VersionSuffix ' (does not exist)'
    }
}

$color = if ($totalErrors -eq 0) { 'Green' } else { 'Red' }

$needsReviewIssues = @($uniqueIssues | Where-Object { $_.Reason -eq 'needs-review' })
if ($needsReviewIssues.Count -gt 0) {
    Write-Host ''
    Write-Host 'The following marketplace tasks were updated since last manual review:' -ForegroundColor Yellow
    foreach ($issue in $needsReviewIssues) {
        Write-Host "  $($issue.File)" -ForegroundColor Yellow
        Write-Host "    Task           : $($issue.Task)"
        Write-Host "    Last checked   : $($shortNameMapping[$issue.Task -replace '@.*$',''].LastChecked.ToString('yyyy-MM-dd'))"
        Write-Host "    Last updated   : $($issue.LatestVersion)"
        Write-Host "    Reference      : $($issue.Link)"
    }
    Write-Host ''
    Write-Host 'After reviewing, update the LastChecked date in $shortNameMapping.' -ForegroundColor Cyan
}

Write-Host "Check Tasks: $($outdatedIssues.Count) outdated, $($nonExistentIssues.Count) non-existent, $($needsReviewIssues.Count) needs-review, $($unknownTasks.Count) unclassified, $($multiVersionTasks.Count) multi-version, $slugErrors invalid slug(s), $marketplaceErrors not found" -ForegroundColor $color

if ($totalErrors -gt 0) { exit 1 }
