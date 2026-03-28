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

## Key Rules

- Follow `azure-devops-templates.custom.instructions.md` when authoring or editing any template.
- Follow `azure-devops-templates-tests.custom.instructions.md` when authoring or editing test pipelines under `.azuredevops/test/`.
- Every new template outside `.azuredevops/` requires a matching test pipeline under `.azuredevops/test/`.
- Job templates end in `.job.yml`; step templates do not.
- All inline PowerShell uses `pwsh:` and follows `powershell-inline.instructions.md`.
- All standalone `.ps1` scripts follow `powershell.instructions.md`.
