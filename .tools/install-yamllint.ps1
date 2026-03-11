<#
.SYNOPSIS
    Installs yamllint as a globally available tool.

.DESCRIPTION
    Checks whether yamllint is already installed and at or above the required version.
    If not, installs it via pip (Python package manager).
    Exits with code 1 if installation fails or the version requirement cannot be met.

.PARAMETER RequiredVersion
    Minimum yamllint version that must be present after installation.
    Defaults to '1.0.0'. Pass an empty string to skip version enforcement.

.EXAMPLE
    # Install yamllint if not already present
    .\.tools\install-yamllint.ps1

    # Require at least version 1.35.0
    .\.tools\install-yamllint.ps1 -RequiredVersion '1.35.0'
#>
param(
    [string]$RequiredVersion = '1.0.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helper: compare semantic versions ────────────────────────────────────────────────────────
function Compare-Version {
    param([string]$actual, [string]$required)
    $a = [Version]($actual  -replace '^v', '')
    $r = [Version]($required -replace '^v', '')
    return $a -ge $r
}

# ── Check if yamllint is already installed ────────────────────────────────────────────────────
$yamllintCmd = Get-Command yamllint -ErrorAction SilentlyContinue

if ($yamllintCmd) {
    $installedVersion = (yamllint --version 2>&1).Trim() -replace '^yamllint\s+', ''
    Write-Host "yamllint $installedVersion is already installed at: $($yamllintCmd.Source)"

    if ($RequiredVersion -ne '' -and -not (Compare-Version $installedVersion $RequiredVersion)) {
        Write-Host "Installed yamllint $installedVersion is below required $RequiredVersion. Updating..." -ForegroundColor Yellow
    } else {
        Write-Host 'yamllint version requirement satisfied.' -ForegroundColor Green
        exit 0
    }
}

# ── Ensure pip / Python is available ─────────────────────────────────────────────────────────
$pipCmd = Get-Command pip -ErrorAction SilentlyContinue
if (-not $pipCmd) {
    $pipCmd = Get-Command pip3 -ErrorAction SilentlyContinue
}

$usePythonMPip = $false
if (-not $pipCmd) {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
    }
    if ($pythonCmd) {
        $usePythonMPip = $true
    } else {
        Write-Host 'pip was not found. Install Python 3 first: https://www.python.org/downloads/' -ForegroundColor Red
        exit 1
    }
}

# ── Install yamllint ──────────────────────────────────────────────────────────────────────────
Write-Host 'Installing yamllint via pip...' -ForegroundColor Cyan
if ($usePythonMPip) {
    & $pythonCmd.Source -m pip install --upgrade yamllint
} else {
    & $pipCmd.Source install --upgrade yamllint
}

# ── Verify installation ───────────────────────────────────────────────────────────────────────

# Refresh PATH on Windows so the newly installed script is visible
if (-not (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) {
    $IsWindows = $env:OS -eq 'Windows_NT'
}
if ($IsWindows) {
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User')

    # Always add the Python Scripts directory — it may not be registered in PATH
    # even when pip itself was found (e.g. on Windows Store / custom Python installs).
    $resolvedPython = if ($usePythonMPip) { $pythonCmd.Source } else { $null }
    if (-not $resolvedPython) {
        $pyCmd = Get-Command python -ErrorAction SilentlyContinue
        if ($pyCmd) { $resolvedPython = $pyCmd.Source }
    }
    if ($resolvedPython) {
        $pythonScripts = & $resolvedPython -c "import sys, os; print(os.path.join(sys.prefix, 'Scripts'))" 2>$null
        if ($pythonScripts -and (Test-Path $pythonScripts)) {
            $env:PATH = $env:PATH + ';' + $pythonScripts
        }
    }
}

$yamllintCmd = Get-Command yamllint -ErrorAction SilentlyContinue
if (-not $yamllintCmd) {
    Write-Host 'yamllint was not found after installation. Verify pip completed successfully.' -ForegroundColor Red
    exit 1
}

$installedVersion = (yamllint --version 2>&1).Trim() -replace '^yamllint\s+', ''
Write-Host "yamllint $installedVersion installed at: $($yamllintCmd.Source)" -ForegroundColor Green

if ($RequiredVersion -ne '' -and -not (Compare-Version $installedVersion $RequiredVersion)) {
    Write-Host "yamllint $installedVersion does not satisfy required version $RequiredVersion." -ForegroundColor Red
    exit 1
}
