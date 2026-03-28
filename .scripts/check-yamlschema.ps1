<#
.SYNOPSIS
    Compares the local yamlschema.json against the live schema from Azure DevOps.

.DESCRIPTION
    Downloads the Azure DevOps YAML pipeline schema and does a canonical JSON
    comparison against the local copy.  Exits with code 1 when they differ so
    the build fails.  Exits with code 2 on a download or parse error.

.PARAMETER SchemaPath
    Path to the local schema file.  Defaults to 'yamlschema.json' in the
    current directory.

.PARAMETER Organization
    Azure DevOps organisation name used to build the schema URL.
    Defaults to 'godeltech'.

.PARAMETER RemoteUrl
    URL of the live Azure DevOps YAML schema endpoint.
    Defaults to https://dev.azure.com/<Organization>/_apis/distributedtask/yamlschema

.PARAMETER AccessToken
    Optional Personal Access Token (or $(System.AccessToken) in CI) to
    authenticate against the Azure DevOps REST API.
    When omitted the request is made without authorisation headers.

.EXAMPLE
    # Local run (schema is publicly accessible)
    .\.scripts\check-yamlschema.ps1

    # CI — pipe in the pipeline token
    .\.scripts\check-yamlschema.ps1 -AccessToken $env:SYSTEM_ACCESSTOKEN
#>
param(
    [string]$SchemaPath   = 'yamlschema.json',
    [string]$Organization = 'godeltech',
    [string]$RemoteUrl    = '',
    [string]$AccessToken  = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RemoteUrl -eq '') {
    $RemoteUrl = "https://dev.azure.com/$Organization/_apis/distributedtask/yamlschema"
}

# ── Helpers ───────────────────────────────────────────────────────────────────

function ConvertTo-CanonicalJson {
    <#
    .SYNOPSIS
        Normalises a JSON string for deterministic equality comparison.
    .DESCRIPTION
        Parses the JSON into a live object then re-serialises with consistent
        indentation so that two semantically identical documents compare equal
        regardless of original whitespace or key ordering.
    .PARAMETER Json
        Raw JSON string to normalise.
    .OUTPUTS
        [hashtable] With keys:
          Compressed - single-line JSON for equality comparison.
          Pretty     - indented JSON for human-readable diff output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Json
    )
    $obj        = $Json | ConvertFrom-Json
    $compressed = $obj | ConvertTo-Json -Depth 100 -Compress
    $pretty     = $obj | ConvertTo-Json -Depth 100
    return @{ Compressed = $compressed; Pretty = $pretty }
}

# ── Verify local file exists ──────────────────────────────────────────────────

if (-not (Test-Path $SchemaPath)) {
    Write-Host "ERROR: Local schema file not found: $SchemaPath" -ForegroundColor Red
    exit 2
}

# ── Download remote schema ────────────────────────────────────────────────────

Write-Host "Fetching remote schema from: $RemoteUrl"

$headers = @{ 'Accept' = 'application/json' }
if ($AccessToken -ne '') {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AccessToken"))
    $headers['Authorization'] = "Basic $encoded"
}

try {
    $response = Invoke-WebRequest -Uri $RemoteUrl -Headers $headers -UseBasicParsing -ErrorAction Stop
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -in @(401, 403)) {
        Write-Host ""
        Write-Host "ERROR: Access denied (HTTP $statusCode)." -ForegroundColor Red
        Write-Host "Provide a Personal Access Token with 'Read' scope via -AccessToken." -ForegroundColor Yellow
        Write-Host "In Azure DevOps pipelines pass: -AccessToken `$env:SYSTEM_ACCESSTOKEN" -ForegroundColor Yellow
    } else {
        Write-Host "ERROR: Failed to download remote schema. $_" -ForegroundColor Red
    }
    exit 2
}

# Azure DevOps returns HTTP 203 with an HTML sign-in page when the org requires
# authentication and none (or an invalid token) was supplied.
$contentType = $response.Headers['Content-Type']
$isJson      = $contentType -like '*json*' -or $response.Content.TrimStart().StartsWith('{')
if (-not $isJson) {
    Write-Host ""
    Write-Host "ERROR: Remote endpoint returned non-JSON content (HTTP $($response.StatusCode))." -ForegroundColor Red
    Write-Host "The Azure DevOps organisation requires authentication." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Local run - provide a PAT:" -ForegroundColor Cyan
    Write-Host "  .\.scripts\check-yamlschema.ps1 -AccessToken '<your-PAT>'"
    Write-Host ""
    Write-Host "In an Azure DevOps pipeline - enable OAuth token and pass it:" -ForegroundColor Cyan
    Write-Host "  env:"
    Write-Host "    SYSTEM_ACCESSTOKEN: `$(System.AccessToken)"
    Write-Host "  arguments: '-AccessToken `$env:SYSTEM_ACCESSTOKEN'"
    Write-Host ""
    Write-Host "To create a PAT: https://dev.azure.com/$Organization/_usersSettings/tokens"
    exit 2
}

# ── Canonicalise both documents ───────────────────────────────────────────────

Write-Host "Comparing schemas..."

try {
    $localJson  = Get-Content -Path $SchemaPath -Raw
    $localCanon = ConvertTo-CanonicalJson $localJson
} catch {
    Write-Host "ERROR: Failed to parse local schema: $_" -ForegroundColor Red
    exit 2
}

try {
    $remoteCanon = ConvertTo-CanonicalJson $response.Content
} catch {
    Write-Host "ERROR: Failed to parse remote schema: $_" -ForegroundColor Red
    exit 2
}

# ── Compare ───────────────────────────────────────────────────────────────────

if ($localCanon.Compressed -eq $remoteCanon.Compressed) {
    Write-Host "Schema check passed - local yamlschema.json matches the remote schema." -ForegroundColor Green
    exit 0
}

# Produce a diff to make the mismatch actionable
$localFile  = [System.IO.Path]::GetTempFileName()
$remoteFile = [System.IO.Path]::GetTempFileName()
try {
    # Write pretty-printed JSON so diff can show meaningful line-numbered hunks
    Set-Content -Path $localFile  -Value $localCanon.Pretty  -Encoding UTF8
    Set-Content -Path $remoteFile -Value $remoteCanon.Pretty -Encoding UTF8

    Write-Host ""
    Write-Host "Schema check FAILED - local and remote schemas differ." -ForegroundColor Red
    Write-Host ""

    # Show a compact diff when the diff utility is available, otherwise give guidance
    $diffCmd = Get-Command diff -ErrorAction SilentlyContinue
    if ($diffCmd) {
        & diff --unified=3 $localFile $remoteFile | Select-Object -First 80 | ForEach-Object {
            $color = if ($_ -like '+*') { 'Green' } elseif ($_ -like '-*') { 'Red' } else { 'Gray' }
            Write-Host $_ -ForegroundColor $color
        }
    } else {
        $localLen  = $localCanon.Compressed.Length
        $remoteLen = $remoteCanon.Compressed.Length
        Write-Host "  Local  : $localLen characters" -ForegroundColor Yellow
        Write-Host "  Remote : $remoteLen characters" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Update the local file by running:" -ForegroundColor Cyan
    Write-Host "  Invoke-WebRequest -Uri '$RemoteUrl' -OutFile '$SchemaPath'"
    Write-Host ""
} finally {
    Remove-Item -Path $localFile, $remoteFile -ErrorAction SilentlyContinue
}

exit 1
