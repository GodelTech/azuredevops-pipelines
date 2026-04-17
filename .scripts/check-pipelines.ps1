<#
.SYNOPSIS
    Verifies that every Azure DevOps test pipeline YAML file has a corresponding
    pipeline in the Azure DevOps project.

.DESCRIPTION
    Walks all *.yml files under the .azuredevops/test folder and checks that each
    one has a matching pipeline in the Azure DevOps project by comparing the
    file's repository-relative path against the configuration.path returned by
    the Azure DevOps Pipelines REST API.
    Exits with code 1 if any files are missing a pipeline so the build fails.
    Exits with code 2 on an API communication error.

.PARAMETER Organization
    Azure DevOps organisation name.
    Defaults to 'godeltech'.

.PARAMETER Project
    Azure DevOps project name.
    Defaults to 'OpenSource'.

.PARAMETER AccessToken
    Optional Personal Access Token (or $(System.AccessToken) in CI) to
    authenticate against the Azure DevOps REST API.
    When omitted the request is made without authorisation headers.

.PARAMETER TestPath
    Path to the folder that contains test pipeline YAML files.
    Defaults to '.azuredevops/test' relative to the repository root
    (one level above this script).

.PARAMETER WarningExitCode
    Exit code to use when duplicate pipelines are found for a YAML file.
    Defaults to 1 (duplicate pipelines fail the build).
    Set to 0 to treat duplicate pipelines as informational only.

.PARAMETER RepositoryFullName
    Expected repository full name that the pipeline's configuration.repository.fullName must match.
    Defaults to 'GodelTech/azuredevops-pipelines'.
    Set to '' to skip the repository full name check.

.PARAMETER RepositoryType
    Expected repository type that the pipeline's configuration.repository.type must match.
    Defaults to 'gitHub'.
    Set to '' to skip the repository type check.

.EXAMPLE
    # Run from the repository root
    .\.scripts\check-pipelines.ps1

    # Run with explicit credentials
    .\.scripts\check-pipelines.ps1 -Organization godeltech -Project OpenSource -AccessToken <PAT>

    # Check repository as well
    .\.scripts\check-pipelines.ps1 -RepositoryFullName 'GodelTech/azuredevops-pipelines' -RepositoryType gitHub

    # Fail the build on duplicate pipelines
    .\.scripts\check-pipelines.ps1 -AccessToken $env:SYSTEM_ACCESSTOKEN -WarningExitCode 1

    # In Azure DevOps pipelines pass:
    .\.scripts\check-pipelines.ps1 -AccessToken $env:SYSTEM_ACCESSTOKEN
#>
param(
    [string]$Organization        = 'godeltech',
    [string]$Project             = 'OpenSource',
    [string]$AccessToken         = '',
    [string]$TestPath            = '',
    [int]   $WarningExitCode     = 1,
    [string]$RepositoryFullName  = 'GodelTech/azuredevops-pipelines',
    [string]$RepositoryType      = 'gitHub'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Resolve paths -----------------------------------------------------------------------------
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if ($TestPath -eq '') {
    $TestPath = Join-Path $repoRoot '.azuredevops\test'
}

# -- Build request headers ---------------------------------------------------------------------
$headers = @{ 'Accept' = 'application/json' }
if ($AccessToken -ne '') {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AccessToken"))
    $headers['Authorization'] = "Basic $encoded"
}

# -- Helper ------------------------------------------------------------------------------------
function Invoke-AzureDevOpsApi {
    <#
    .SYNOPSIS
        Sends a GET request to the Azure DevOps REST API.
    .DESCRIPTION
        Wraps Invoke-WebRequest with the pre-built authorization headers. Exits with
        code 2 on HTTP 401/403 (authentication errors) or any other request failure,
        printing an actionable error message before exiting.
    .PARAMETER Url
        Full URL of the Azure DevOps REST API endpoint to call.
    .OUTPUTS
        [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] The raw response object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )
    try {
        return Invoke-WebRequest -Uri $Url -Headers $headers -UseBasicParsing -ErrorAction Stop
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -in @(401, 403)) {
            Write-Host ''
            Write-Host "ERROR: Access denied (HTTP $statusCode)." -ForegroundColor Red
            Write-Host "Provide a Personal Access Token with 'Read' scope via -AccessToken." -ForegroundColor Yellow
            Write-Host 'In Azure DevOps pipelines pass: -AccessToken $env:SYSTEM_ACCESSTOKEN' -ForegroundColor Yellow
        } else {
            Write-Host "ERROR: API request failed. $_" -ForegroundColor Red
        }
        exit 2
    }
}

# -- Collect local test YAML files -------------------------------------------------------------
if (-not (Test-Path $TestPath)) {
    Write-Host "ERROR: Test path not found: $TestPath" -ForegroundColor Red
    exit 2
}

$testFiles = Get-ChildItem -Path $TestPath -Recurse -Filter '*.yml'

if ($testFiles.Count -eq 0) {
    Write-Host "No YAML files found under: $TestPath" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($testFiles.Count) test YAML file(s) to verify."

# -- Fetch all pipelines from Azure DevOps (paginated) -----------------------------------------
$apiBase = "https://dev.azure.com/$Organization/$Project/_apis/pipelines"
$allPipelines = [System.Collections.Generic.List[object]]::new()
$continuationToken = $null

Write-Host "Fetching pipelines from: $apiBase"

do {
    $url = "${apiBase}?api-version=7.1"
    if ($continuationToken) { $url += "&continuationToken=$continuationToken" }

    $response = Invoke-AzureDevOpsApi -Url $url

    $contentType = $response.Headers['Content-Type']
    $isJson = $contentType -like '*json*' -or $response.Content.TrimStart().StartsWith('{')
    if (-not $isJson) {
        Write-Host ''
        Write-Host 'ERROR: Unexpected response (not JSON). The organisation or project may require authentication.' -ForegroundColor Red
        Write-Host 'Provide a Personal Access Token via -AccessToken.' -ForegroundColor Yellow
        exit 2
    }

    $data = $response.Content | ConvertFrom-Json
    foreach ($pipeline in $data.value) {
        $allPipelines.Add($pipeline)
    }

    $continuationToken = $response.Headers['x-ms-continuationtoken']
} while ($continuationToken)

Write-Host "Retrieved $($allPipelines.Count) pipeline(s) from Azure DevOps."

# -- Fetch configuration.path for each pipeline ------------------------------------------------
Write-Host 'Fetching pipeline configuration paths...'

$pipelinePaths = @{}

foreach ($pipeline in $allPipelines) {
    $detailUrl = "${apiBase}/$($pipeline.id)?api-version=7.1"
    $detailResponse = Invoke-AzureDevOpsApi -Url $detailUrl
    $detail = $detailResponse.Content | ConvertFrom-Json

    if ($detail.configuration -and $detail.configuration.path) {
        $normalised = $detail.configuration.path.TrimStart('/').Replace('\', '/').ToLowerInvariant()
        if (-not $pipelinePaths.ContainsKey($normalised)) {
            $pipelinePaths[$normalised] = [System.Collections.Generic.List[object]]::new()
        }
        $pipelinePaths[$normalised].Add([PSCustomObject]@{
            Name               = $pipeline.name
            Id                 = $pipeline.id
            RepositoryFullName = if ($detail.configuration.repository -and $detail.configuration.repository.PSObject.Properties['fullName']) { $detail.configuration.repository.fullName } else { '' }
            RepositoryType     = if ($detail.configuration.repository -and $detail.configuration.repository.PSObject.Properties['type']) { $detail.configuration.repository.type } else { '' }
        })
    }
}

# -- Check each local test file ----------------------------------------------------------------
$issues   = @()
$warnings = @()

foreach ($file in $testFiles) {
    $repoRelative = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    $normalised = $repoRelative.ToLowerInvariant()

    if ($pipelinePaths.ContainsKey($normalised)) {
        $matches = @($pipelinePaths[$normalised] | Where-Object {
            ($RepositoryFullName -eq '' -or $_.RepositoryFullName -ieq $RepositoryFullName) -and
            ($RepositoryType     -eq '' -or $_.RepositoryType     -ieq $RepositoryType)
        })
        if ($matches.Count -eq 0) {
            Write-Host "  [MISSING] $repoRelative" -ForegroundColor Red
            $issues += [PSCustomObject]@{ File = $file.FullName; RelativePath = $repoRelative }
        }
        elseif ($matches.Count -gt 1) {
            Write-Host "  [WARNING] $repoRelative  ($($matches.Count) pipelines found)" -ForegroundColor Yellow
            $warnings += [PSCustomObject]@{ RelativePath = $repoRelative; Count = $matches.Count }
            foreach ($match in $matches) {
                $buildUrl = "https://dev.azure.com/$Organization/$Project/_build?definitionId=$($match.Id)"
                Write-Host "            Name:       $($match.Name)" -ForegroundColor Yellow
                Write-Host "            Repository: $($match.RepositoryFullName) ($($match.RepositoryType))" -ForegroundColor Yellow
                Write-Host "            URL:        $buildUrl" -ForegroundColor Yellow
            }
        }
        else {
            $match = $matches[0]
            $buildUrl = "https://dev.azure.com/$Organization/$Project/_build?definitionId=$($match.Id)"
            Write-Host "  [OK]      $repoRelative" -ForegroundColor Green
            Write-Host "            Name:       $($match.Name)" -ForegroundColor Green
            Write-Host "            Repository: $($match.RepositoryFullName) ($($match.RepositoryType))" -ForegroundColor Green
            Write-Host "            URL:        $buildUrl" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  [MISSING] $repoRelative" -ForegroundColor Red
        $issues += [PSCustomObject]@{ File = $file.FullName; RelativePath = $repoRelative }
    }
}

# -- Report results ----------------------------------------------------------------------------
if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host ''
    Write-Host 'All test pipeline YAML files have a corresponding Azure DevOps pipeline.' -ForegroundColor Green
}

if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host 'The following test YAML files have more than one Azure DevOps pipeline:' -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "  - $($warning.RelativePath)  ($($warning.Count) pipelines found)" -ForegroundColor Yellow
    }
}

if ($issues.Count -gt 0) {
    Write-Host ''
    Write-Host 'The following test YAML files do not have a corresponding Azure DevOps pipeline:' -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  - $($issue.RelativePath)" -ForegroundColor Red
    }
}

if ($issues.Count -gt 0) {
    exit 1
}

if ($warnings.Count -gt 0 -and $WarningExitCode -ne 0) {
    exit $WarningExitCode
}
