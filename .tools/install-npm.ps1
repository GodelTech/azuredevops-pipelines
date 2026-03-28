<#
.SYNOPSIS
    Installs Node.js / npm as a globally available tool.

.DESCRIPTION
    Checks whether npm is already installed and at or above the required version.
    If not, downloads and installs Node.js (which bundles npm) using the platform
    package manager when available, or falls back to the official Node.js MSI/pkg
    installer on Windows/macOS.
    Exits with code 1 if installation fails or the version requirement cannot be met.

.PARAMETER RequiredVersion
    Minimum npm version that must be present after installation.
    Defaults to '10.0.0'. Pass an empty string to skip version enforcement.

.PARAMETER NodeVersion
    Node.js release to install if npm is not already present.
    Accepts 'lts' or an exact version such as '22.14.0'.
    Defaults to 'lts'.

.EXAMPLE
    # Install the LTS Node.js bundle (includes npm) if not already present
    .\.tools\install-npm.ps1

    # Require at least npm 10 and install Node.js 22.x if needed
    .\.tools\install-npm.ps1 -RequiredVersion '10.0.0' -NodeVersion '22.14.0'
#>
param(
    [string]$RequiredVersion = '10.0.0',
    [string]$NodeVersion     = 'lts'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Platform detection (PowerShell 5.1 does not define these automatic variables) ─────────────
if (-not (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) {
    $IsWindows = $env:OS -eq 'Windows_NT'
    $IsLinux   = $false
    $IsMacOS   = $false
}

# ── Helper: compare semantic versions ────────────────────────────────────────────────────────
function Compare-Version {
    <#
    .SYNOPSIS
        Compares two semantic version strings.
    .DESCRIPTION
        Returns $true when the actual version is greater than or equal to the required version.
        Leading 'v' prefixes are stripped before comparison.
    .PARAMETER Actual
        The version string currently installed (e.g. '10.2.3' or 'v10.2.3').
    .PARAMETER Required
        The minimum acceptable version string (e.g. '10.0.0').
    .OUTPUTS
        [bool] $true when Actual >= Required, otherwise $false.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Actual,

        [Parameter(Mandatory)]
        [string]$Required
    )
    $a = [Version]($Actual  -replace '^v', '')
    $r = [Version]($Required -replace '^v', '')
    return $a -ge $r
}

# ── Check if npm is already installed ────────────────────────────────────────────────────────
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue

if ($npmCmd) {
    $installedVersion = (npm --version).Trim()
    Write-Host "npm $installedVersion is already installed at: $($npmCmd.Source)"

    if ($RequiredVersion -ne '' -and -not (Compare-Version $installedVersion $RequiredVersion)) {
        Write-Host "Installed npm $installedVersion is below required $RequiredVersion. Updating..." -ForegroundColor Yellow
    } else {
        Write-Host "npm version requirement satisfied." -ForegroundColor Green
        exit 0
    }
}

# ── Install Node.js (which bundles npm) ──────────────────────────────────────────────────────
Write-Host "Installing Node.js ($NodeVersion) to obtain npm..." -ForegroundColor Cyan

if ($IsWindows -or $env:OS -eq 'Windows_NT') {

    # Prefer winget, fall back to manual MSI download
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        $packageId = 'OpenJS.NodeJS.LTS'
        if ($NodeVersion -ne 'lts' -and $NodeVersion -ne '') {
            $packageId = 'OpenJS.NodeJS'
        }
        Write-Host "Installing via winget: $packageId"
        winget install --id $packageId --exact --accept-source-agreements --accept-package-agreements
    } else {
        # Resolve LTS version from nodejs.org
        if ($NodeVersion -eq 'lts') {
            $index   = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
            $ltsNode = $index | Where-Object { $_.lts -ne $false } | Select-Object -First 1
            $NodeVersion = $ltsNode.version
        }

        $msiUrl  = "https://nodejs.org/dist/$NodeVersion/node-$NodeVersion-x64.msi"
        $msiPath = Join-Path $env:TEMP "node-$NodeVersion-x64.msi"

        Write-Host "Downloading $msiUrl"
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

        Write-Host "Running installer: $msiPath"
        Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -NoNewWindow

        Remove-Item $msiPath -Force
    }

} elseif ($IsMacOS) {

    $brew = Get-Command brew -ErrorAction SilentlyContinue
    if (-not $brew) {
        Write-Host 'Homebrew is required to install Node.js on macOS but was not found.' -ForegroundColor Red
        exit 1
    }
    brew install node

} elseif ($IsLinux) {

    if (Get-Command apt-get -ErrorAction SilentlyContinue) {
        sudo apt-get update -qq
        sudo apt-get install -y nodejs npm
    } elseif (Get-Command dnf -ErrorAction SilentlyContinue) {
        sudo dnf install -y nodejs npm
    } elseif (Get-Command yum -ErrorAction SilentlyContinue) {
        sudo yum install -y nodejs npm
    } else {
        Write-Host 'No supported package manager found (apt-get / dnf / yum).' -ForegroundColor Red
        exit 1
    }

} else {
    Write-Host 'Unsupported platform. Install Node.js manually from https://nodejs.org/' -ForegroundColor Red
    exit 1
}

# ── Verify installation ───────────────────────────────────────────────────────────────────────

# Refresh PATH in the current session so the newly installed npm is visible
# (Windows stores PATH in the registry; Linux/macOS package managers update it in place)
if ($IsWindows) {
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User')
}

$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npmCmd) {
    Write-Host 'npm was not found after installation. Verify the Node.js installer completed successfully.' -ForegroundColor Red
    exit 1
}

$installedVersion = (npm --version).Trim()
Write-Host "npm $installedVersion installed at: $($npmCmd.Source)" -ForegroundColor Green

if ($RequiredVersion -ne '' -and -not (Compare-Version $installedVersion $RequiredVersion)) {
    Write-Host "npm $installedVersion does not satisfy required version $RequiredVersion." -ForegroundColor Red
    exit 1
}

Write-Host "npm installation complete." -ForegroundColor Green
