---
applyTo: '.azuredevops/test/**/*.yml'
description: 'Conventions for authoring test pipelines for Azure DevOps templates in this repository'
---

# Test Pipeline Authoring Conventions

Every template outside `.azuredevops/` must have a corresponding test pipeline under `.azuredevops/test/`
at the same relative path, with a `.test.yml` suffix (e.g. `dotnet/dotnet/restore.yml` →
`.azuredevops/test/dotnet/dotnet/restore.test.yml`). This is enforced by `check-test-coverage.ps1`.

## Parameter Block

Test pipelines always declare at minimum `enableBuildDebug` (defaulting to `true`) and `vmImage`:

```yaml
parameters:
  - name: enableBuildDebug
    displayName: 'Enable build debug'
    type: boolean
    default: true

  - name: vmImage
    displayName: 'Pool VM image'
    type: string
    default: 'ubuntu-latest'
    values:
      - windows-latest
      - ubuntu-latest
      - macOS-latest
```

## Trigger Block

Every test pipeline must have `batch: true` and list its own path plus all referenced template
paths in `paths.include`:

```yaml
trigger:
  batch: true
  paths:
    include:
      - .azuredevops/test/dotnet/dotnet/restore.test.yml
      - dotnet/dotnet/install-SDK.yml
      - dotnet/dotnet/restore.yml
      - .azuredevops/testHelpers/build-summary-validation.job.yml
```

## PR Block

The `pr:` block must include `branches: include: ['*']` and the same `paths.include` list as `trigger:`:

```yaml
pr:
  branches:
    include:
      - '*'
  paths:
    include:
      - .azuredevops/test/dotnet/dotnet/restore.test.yml
      - dotnet/dotnet/install-SDK.yml
      - dotnet/dotnet/restore.yml
      - .azuredevops/testHelpers/build-summary-validation.job.yml
```

## Schedules Block

Every test pipeline must contain exactly this monthly schedule block:

```yaml
schedules:
  - cron: '0 0 1 * *'
    displayName: 'Monthly check'
    branches:
      include:
        - main
    always: true
```

## Build Summary Validation — Last Job Requirement

The **last job** in every test pipeline must be a reference to one of the two `build-summary-validation`
helpers. This is enforced by `check-build-summary-validation.ps1`.

Use the job helper when the tested template is itself a job template:

```yaml
- template: '../../../.azuredevops/testHelpers/build-summary-validation.job.yml'
  parameters:
    enableBuildDebug: ${{ parameters.enableBuildDebug }}
    vmImage: ${{ parameters.vmImage }}
    dependsOn:
      - MyTestedJob
    expectedBuildResult: 'Succeeded'
    buildResultDescription: |
      Job **'My tested job'** result must be: **Succeeded**
```

Use the step helper (inside a job) when the tested template is a step template:

```yaml
- template: '../../../../.azuredevops/testHelpers/build-summary-validation.yml'
  parameters:
    enableBuildDebug: ${{ parameters.enableBuildDebug }}
    expectedBuildResult: 'Succeeded'
    buildResultDescription: |
      Step **'my step'** result must be: **Succeeded**
```

## File Header Comment

Add a comment on line 1 with the logical name of the test pipeline, matching the file path:

```yaml
# test-dotnet-dotnet-restore.test.yml
```
