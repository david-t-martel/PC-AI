# DOC_STATUS

Generated: 2026-01-28 17:29:22

## Counts
- TODO: 16
- FIXME: 2
- INCOMPLETE: 2
- DEPRECATED: 3
- @status: 1

## Matches
- C:\Users\david\PC_AI\AGENTS.md 56:## Known gaps / TODOs
- C:\Users\david\PC_AI\Deploy\rust-functiongemma-train\TODO.md 1:# TODO - Rust FunctionGemma (PC_AI)
- C:\Users\david\PC_AI\Deploy\rust-functiongemma-train\TODO.md 3:This TODO captures the minimum work required to reach feature parity with
- C:\Users\david\PC_AI\rules\doc-status.yml 7:    - pattern: "TODO"
- C:\Users\david\PC_AI\rules\doc-status.yml 8:    - pattern: "FIXME"
- C:\Users\david\PC_AI\rules\doc-status.yml 9:    - pattern: "INCOMPLETE"
- C:\Users\david\PC_AI\rules\doc-status.yml 10:    - pattern: "DEPRECATED"
- C:\Users\david\PC_AI\Tools\update-doc-status.ps1 8:  Scans the repo for TODO/FIXME/INCOMPLETE/@status/DEPRECATED markers and writes:
- C:\Users\david\PC_AI\Tools\update-doc-status.ps1 36:$markers = 'TODO|FIXME|INCOMPLETE|@status|DEPRECATED'
- C:\Users\david\PC_AI\Tools\update-doc-status.ps1 117:    if ($_.Match -match 'TODO') { 'TODO' }
- C:\Users\david\PC_AI\Tools\update-doc-status.ps1 118:    elseif ($_.Match -match 'FIXME') { 'FIXME' }
- C:\Users\david\PC_AI\Tools\update-doc-status.ps1 119:    elseif ($_.Match -match 'INCOMPLETE') { 'INCOMPLETE' }
- C:\Users\david\PC_AI\Tools\update-doc-status.ps1 120:    elseif ($_.Match -match '@status') { '@status' }
- C:\Users\david\PC_AI\Tools\update-doc-status.ps1 121:    elseif ($_.Match -match 'DEPRECATED') { 'DEPRECATED' }
- C:\Users\david\PC_AI\Tools\Invoke-DocPipeline.ps1 98:# Step 1: Generate DOC_STATUS report (TODO/FIXME/DEPRECATED markers)
- C:\Users\david\PC_AI\Tools\test-rg.ps1 5:$markers = 'TODO|FIXME|INCOMPLETE|@status|DEPRECATED'
- C:\Users\david\PC_AI\TODO.md 1:# TODO
- C:\Users\david\PC_AI\Deploy\rust-functiongemma-train\README.md 20:   - FunctionGemma model inference with tool-call parsing (TODO)
- C:\Users\david\PC_AI\Deploy\rust-functiongemma-train\README.md 26:   - LoRA/QLoRA fine-tuning (TODO)
- C:\Users\david\PC_AI\Deploy\rust-functiongemma-train\README.md 27:   - Eval harness + regression checks (TODO)
- C:\Users\david\PC_AI\Deploy\rust-functiongemma-train\README.md 149:with the Python pipeline and has several TODOs (see TODO.md).
- C:\Users\david\PC_AI\Modules\PC-AI.Acceleration\Public\Search-ContentFast.ps1 39:    Search-ContentFast -Path "." -LiteralPattern "TODO:" -Context 2
- C:\Users\david\PC_AI\Modules\PC-AI.Acceleration\Public\Search-ContentFast.ps1 40:    Finds TODO comments with context
- C:\Users\david\PC_AI\Deploy\functiongemma-finetune\tool_router.py 2:# DEPRECATED: prefer native C# routing via PcaiOpenAiClient + Invoke-FunctionGemmaReAct.

