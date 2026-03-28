---
applyTo: '**/*.yml,**/*.yaml'
description: 'Best practices for inline PowerShell scripts embedded in Azure DevOps YAML pipeline files'
---

# Inline PowerShell in Azure DevOps YAML Pipeline Files

For standalone `.ps1` and `.psm1` scripts, follow the rules in
[powershell.instructions.md](powershell.instructions.md).

Inline scripts embedded in `pwsh:` or `script:` YAML steps follow different rules from
standalone `.ps1` files. Apply these guidelines when writing or reviewing inline blocks.

## Key Differences from Standalone Scripts

- **No `[CmdletBinding()]` or `param()` blocks** — inline scripts are flat code, not functions
- **2-space indentation** — match the surrounding YAML indentation, not the 4-space PS convention
- **`Write-Host` is appropriate** — it produces visible output in the pipeline log
- **No comment-based help** — use the step's `displayName:` to document intent instead
- **Keep scripts short** — extract logic longer than ~20 lines into a dedicated `.ps1` file

## Reading Pipeline Variables

- Always read pipeline variables via `$env:VARIABLE_NAME` mapped through the step's `env:` block
- Never inject pipeline variables directly with `${{ parameters.x }}` or `$(variable)` inside
  script logic — only use template expressions for values that must be known at queue time
  (e.g. task inputs, condition expressions)
- **Declare every `$env:` variable as a named local variable at the very top of the script**,
  before any logic. Never use `$env:` references inline throughout the script body.
- Use `[System.Convert]::ToBoolean($env:VAR)` to coerce string env vars to booleans

```yaml
- pwsh: |
    $noRestore = [System.Convert]::ToBoolean($env:NO_RESTORE)
    $publishReport = [System.Convert]::ToBoolean($env:PUBLISH_REPORT)

    # all logic below uses $noRestore / $publishReport, never $env:NO_RESTORE etc.
  displayName: 'Set arguments'
  env:
    NO_RESTORE: ${{ parameters.noRestore }}
    PUBLISH_REPORT: ${{ parameters.publishReport }}
```

## Azure DevOps Logging Commands

- Set output variables with `Write-Host "##vso[task.setvariable variable=NAME;isOutput=true]VALUE"`
- Log warnings with `Write-Host "##vso[task.logissue type=warning]MESSAGE"`
- Log errors with `Write-Host "##vso[task.logissue type=error]MESSAGE"`
- Do **not** use `Write-Warning` or `Write-Error` for issues that must appear in the pipeline UI

```yaml
- pwsh: |
    if ($value -eq $expected) {
      Write-Host '##vso[task.setvariable variable=matchResult;isOutput=true]Matched'
    } else {
      Write-Host "##vso[task.logissue type=warning]Value '$value' does not match '$expected'"
      Write-Host '##vso[task.setvariable variable=matchResult;isOutput=true]Mismatched'
    }
  displayName: 'Check output variable'
  env:
    EXPECTED_VALUE: ${{ parameters.expectedValue }}
```

## Error Handling in Inline Scripts

- Use `try/catch` for operations that may fail
- Use `exit 1` (not `throw`) to fail the step with a clean message, unless re-throwing
  is needed to preserve the original exception
- For REST API calls use `-ErrorAction Stop` so failures are caught by `catch`

```yaml
- pwsh: |
    $apiUrl = $env:API_URL

    try {
      $response = Invoke-RestMethod -Uri $apiUrl -Method Patch -Headers $headers -Body $body -ErrorAction Stop
    } catch {
      Write-Host "##vso[task.logissue type=error]API call failed: $_"
      exit 1
    }
  displayName: 'Call API'
  env:
    API_URL: $(System.CollectionUri)
```

## String Interpolation in URLs

When embedding a variable directly before `?` in a URL string, PowerShell's interpolation
parser treats `$var?rest` as one variable name (`${var?rest}`), which evaluates to empty.
Always use `${varName}` to explicitly close the variable reference when it is immediately
followed by `?`, `[`, or any non-alphanumeric/non-underscore character inside a
double-quoted string.

```yaml
# WRONG — $buildId?api is parsed as one variable name → buildId is empty in the URL
$url = "$collectionUri$teamProject/_apis/build/builds/$buildId?api-version=7.1"

# CORRECT — ${buildId} explicitly closes the variable reference
$url = "$collectionUri$teamProject/_apis/build/builds/${buildId}?api-version=7.1"
```

## Style Rules (inline-specific)

- Use `camelCase` for local variables (not PascalCase — reduces noise vs pipeline variable names)
- No aliases — use full cmdlet names (`ForEach-Object`, `Where-Object`, etc.)
- Avoid `Out-Null` suppression inside inline scripts; prefer `| Out-Null` only when
  the return value is truly unused (e.g. `New-Item ... | Out-Null`)
