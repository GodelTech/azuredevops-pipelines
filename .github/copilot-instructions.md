# Azure DevOps Pipeline Template Library

This repository is a **reusable Azure DevOps pipeline template library** maintained by GodelTech.
Every YAML file is a template meant to be consumed by other repositories via `template:` blocks —
not a standalone pipeline.

## Repository Structure

- `azuredevops/` — infrastructure step templates (job wrapper, build summary, cancel build)
- `dotnet/` — .NET build, restore, format, NuGet package checks, SonarCloud integration
- `git/version/` — GitVersion job template
- `.azuredevops/` — this repo's own CI pipeline and test pipelines for every template
- `.azuredevops/testHelpers/` — shared helpers used at the end of every test pipeline
- `.azuredevops/dummy-projects/` — real .NET projects used by test pipeline runs
- `.scripts/` — PowerShell validation scripts run as build tasks and in CI
- `.tools/` — PowerShell tool installer scripts

## Instruction Files

Follow these instruction files when working in this codebase:

| File | Applies to |
|---|---|
| [azure-devops-templates.instructions.md](.github/instructions/custom/azure-devops-templates.instructions.md) | All `.yml` templates — parameter rules, naming, conditional passthrough |
| [azure-devops-templates-tests.instructions.md](.github/instructions/custom/azure-devops-templates-tests.instructions.md) | Test pipelines under `.azuredevops/test/` |
| [powershell-inline.instructions.md](.github/instructions/powershell-inline.instructions.md) | Inline `pwsh:` scripts inside `.yml` files |
| [powershell.instructions.md](.github/instructions/powershell.instructions.md) | Standalone `.ps1` and `.psm1` scripts |

## Key Rules

- Every new template outside `.azuredevops/` requires a matching test pipeline under `.azuredevops/test/`.
- Job templates end in `.job.yml`; step templates do not.
- `enableBuildDebug` must be the **first parameter** in every template.
- All inline PowerShell uses `pwsh:` (never `script:`).

## Build / Validation Commands

Run these locally before committing. All are enforced in CI:

```sh
npm install                                          # install prettier
python -m yamllint .                                 # YAML lint
npx prettier . --check                               # formatting (fix: --write)
powershell .scripts/check-template-references.ps1   # all template: paths resolve
powershell .scripts/check-test-coverage.ps1          # every template has a test pipeline
powershell .scripts/check-triggers.ps1              # trigger blocks
powershell .scripts/check-pr.ps1                    # PR blocks
powershell .scripts/check-schedules.ps1             # monthly schedule present
powershell .scripts/check-build-summary-validation.ps1  # last job is validation helper
powershell .scripts/check-cancel-build.ps1
powershell .scripts/check-tasks.ps1
```

## Adding a New Template — Checklist

1. Create the template file at the appropriate path (`step.yml` or `step.job.yml`).
2. Follow all parameter conventions from `azure-devops-templates.instructions.md`.
3. Create a matching test pipeline at `.azuredevops/test/<same-relative-path>/<filename>.test.yml`.
4. In the test pipeline:
   - Add the file-path comment on line 1 (e.g. `# test-dotnet-dotnet-restore.test.yml`).
   - Declare `enableBuildDebug` (default `true`) and `vmImage` parameters.
   - Add `trigger:` and `pr:` blocks with `batch: true` and `paths.include` listing the test file, all referenced templates, and the build-summary-validation helper.
   - Add the monthly `schedules:` block (`cron: '0 0 1 * *'`, `always: true`).
   - Make the last job a reference to `.azuredevops/testHelpers/build-summary-validation.job.yml` (job templates) or `.azuredevops/testHelpers/build-summary-validation.yml` (step templates).
5. Run the full build/validation suite above.

## Non-Obvious Pitfalls

- **`# prettier-ignore`** must be on the line *immediately* before `default:` for `object` params with inline JSON — one blank line breaks it.
- **`paths.include` in test pipelines** must list the `testHelpers/build-summary-validation.job.yml` (or step variant) — omitting it means changes to the helper won't re-trigger the test.
- **Inline scripts must not use `$(var)` or `${{ parameters.x }}` inside PowerShell logic** — only in `env:` mappings or `condition:` fields. Read via `$env:VAR_NAME` mapped through `env:`.
- **`check-test-coverage.ps1` is strict** — adding a template without a test pipeline fails CI.
- **The CI pipeline itself (`.azuredevops/CI.yml`) does not use `enableBuildDebug`** — that convention applies only to reusable templates.
