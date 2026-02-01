# Copilot Instructions (PC_AI)

## Build, Test, Lint
- **Dev setup:** `.Setup-DevEnvironment.ps1` (installs PSScriptAnalyzer, Pester, pre-commit).
- **Lint (PSScriptAnalyzer):** `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1`
- **Tests (all):** `.Tests\.pester.ps1 -Type All -Coverage`
- **Tests (unit):** `.Tests\.pester.ps1 -Type Unit`
- **Tests (integration):** `.Tests\.pester.ps1 -Type Integration`
- **Tests (CI mode):** `.Tests\.pester.ps1 -CI`
- **Run a single test (by name):** `.Tests\.pester.ps1 -TestName "<ModuleOrTestName>"`
- **Run a single test file:** `Invoke-Pester -Path .\Modules\PC-AI.Hardware\Tests\PC-AI.Hardware.Tests.ps1`
- **Local CI simulation (if present):** `.Test-CI-Locally.ps1` (see CI-CD-GUIDE.md)

## High-Level Architecture
- **Entry point:** `PC-AI.ps1` routes CLI commands into PowerShell modules under `Modules\`.
- **Modules:** Hardware/Virtualization/USB/Network/Performance/Cleanup/LLM/Acceleration split by domain.
- **Native acceleration:** Rust DLLs in `Native\` -> C# P/Invoke wrapper -> PowerShell module (`PC-AI.Acceleration`).
- **LLM pipeline:** Optional FunctionGemma router (tool selection via `Config\pcai-tools.json`) runs tools, then **pcai-inference** produces responses.
- **Prompts:** `DIAGNOSE.md` + `DIAGNOSE_LOGIC.md` define diagnose mode; `CHAT.md` defines chat mode.
- **Config:** `Config\llm-config.json` and optional `Config\hvsock-proxy.conf` control endpoints and routing.

## Key Conventions
- **Safety-first:** Diagnostics are read-only by default; destructive actions require explicit confirmation.
- **Diagnostics flow:** collect -> parse -> (optional route) -> reason -> recommend; keep evidence tied to report/log lines.
- **Output contracts:** Diagnose mode output must follow `Config\DIAGNOSE_TEMPLATE.json` (see DIAGNOSE.md / DIAGNOSE_LOGIC.md).
- **PowerShell style:** Use approved verbs, avoid aliases, follow PSScriptAnalyzer rules in `PSScriptAnalyzerSettings.psd1`.
- **LLM tooling updates:** When adding tools, update `Config\pcai-tools.json`, scenarios in `Deploy\rust-functiongemma-train\examples\scenarios.json`, and prompts if diagnostics change.
