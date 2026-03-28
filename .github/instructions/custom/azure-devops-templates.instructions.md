---
applyTo: '**/*.yml'
description: 'Conventions for authoring reusable Azure DevOps pipeline templates in this repository'
---

# Template Authoring Conventions

This repository is a **reusable Azure DevOps pipeline template library**.
Every YAML file is a template consumed by other repositories via `template:` blocks — not a standalone pipeline.

## Parameter Block Rules

- `enableBuildDebug` **must always be the first parameter** in every template, declared exactly as:

  ```yaml
  - name: enableBuildDebug
    displayName: 'Enable build debug'
    type: boolean
    default: false
  ```

- All parameters must have a `displayName` and a `type`.
- `object`-type parameters with an inline JSON `default` must have `# prettier-ignore` on the line immediately before `default:`.

  ```yaml
  - name: outdatedPackages
    displayName: 'Parameters for outdated packages check'
    type: object
    # prettier-ignore
    default: {
      enable: true,
      stepResult: 'SucceededWithIssues'
    }
  ```

- Optional string parameters that the caller may leave unset must default to `''`.

## Conditional Parameter Passthrough

When a parent template forwards an `object` sub-field to a child template, guard each field with
`${{ if ne(..., '') }}:` to avoid overriding the child's default with an empty value:

```yaml
- template: 'child.yml'
  parameters:
    enableBuildDebug: ${{ parameters.enableBuildDebug }}
    ${{ if ne(parameters.options.enable, '') }}:
      enable: ${{ parameters.options.enable }}
    ${{ if ne(parameters.options.stepResult, '') }}:
      stepResult: ${{ parameters.options.stepResult }}
```

## Output Variables and the `stepName` Parameter

Every step template that emits an output variable via `##vso[task.setvariable ...]` must declare a
`stepName` parameter so callers can reference the output. Use the YAML step `name:` key with that value:

```yaml
- name: stepName
  displayName: 'Step name to use as reference'
  type: string
  default: 'my_step'
```

## Optional `condition` Parameter

Step templates that support a caller-supplied condition must accept a `condition: string` parameter
defaulting to `''` and apply it conditionally:

```yaml
${{ if ne(parameters.condition, '') }}:
  condition: ${{ parameters.condition }}
```

## Debug Steps

Wrap debug-only steps in:

```yaml
${{ if eq(parameters.enableBuildDebug, true) }}:
  - pwsh: ...
    displayName: '...'
```

## File Naming

- Job templates must end in `.job.yml` (e.g., `build.job.yml`, `get.job.yml`).
- Step templates must **not** use the `.job.yml` suffix.

## Test Coverage Requirement

Every template outside `.azuredevops/` must have a corresponding test pipeline mirrored under
`.azuredevops/test/` at the same relative path, with a `.test.yml` suffix.
This is enforced by `check-test-coverage.ps1`.

## Long-Line Suppression

When a template expression unavoidably exceeds the 160-character line limit, wrap it with:

```yaml
# yamllint disable rule:line-length
  ${{ parameters.someVeryLongExpression }}
# yamllint enable
```

## PowerShell URL Variables

When a pipeline variable appears in a URL immediately before `?`, use `${varName}` syntax to prevent
PowerShell from parsing `$varName?rest` as a single variable name:

```powershell
$url = "https://dev.azure.com/org/_build/results?buildId=${buildId}&view=logs"
```
