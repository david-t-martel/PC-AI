#Requires -Version 5.1

function Invoke-PCDiagnosis {
    <#
    .SYNOPSIS
        Analyzes PC diagnostic reports using LLM

    .DESCRIPTION
        Main diagnostic analysis function that loads DIAGNOSE.md as system prompt and
        DIAGNOSE_LOGIC.md as reasoning guide, then submits a hardware diagnostic report
        to Ollama for intelligent analysis and recommendations.

    .PARAMETER DiagnosticReportPath
        Path to the hardware diagnostic report text file

    .PARAMETER ReportText
        Direct diagnostic report text (alternative to file path)

    .PARAMETER Model
        The model to use for analysis (default: qwen2.5-coder:7b)

    .PARAMETER Temperature
        Controls analysis consistency (0.0-2.0). Lower = more deterministic. Default: 0.3

    .PARAMETER IncludeRawResponse
        Include the raw LLM response in output

    .PARAMETER SaveReport
        Save the analysis report to a file

    .PARAMETER OutputPath
        Path to save the analysis report (default: Desktop\PC-Diagnosis-Analysis.txt)

    .EXAMPLE
        Invoke-PCDiagnosis -DiagnosticReportPath "C:\Users\david\Desktop\Hardware-Diagnostics-Report.txt"
        Analyzes the diagnostic report and outputs structured findings

    .EXAMPLE
        Get-Content report.txt | Invoke-PCDiagnosis -ReportText $_ -SaveReport
        Analyzes report from pipeline and saves analysis to file

    .EXAMPLE
        Invoke-PCDiagnosis -DiagnosticReportPath report.txt -Model "deepseek-r1:8b" -Temperature 0.1
        Uses DeepSeek model with very low temperature for consistent analysis

    .OUTPUTS
        PSCustomObject with structured analysis findings and recommendations
    #>
    [CmdletBinding(DefaultParameterSetName = 'FromFile')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'FromFile', Position = 0)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$DiagnosticReportPath,

        [Parameter(Mandatory, ParameterSetName = 'FromText', ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$ReportText,

        [Parameter()]
        [string]$Model = $script:ModuleConfig.DefaultModel,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature = 0.3,

        [Parameter()]
        [switch]$IncludeRawResponse,

        [Parameter()]
        [switch]$SaveReport,

        [Parameter()]
        [string]$OutputPath = (Join-Path -Path ([Environment]::GetFolderPath('Desktop')) -ChildPath 'PC-Diagnosis-Analysis.txt')
    )

    begin {
        Write-Verbose "Initializing PC diagnosis analysis..."

        # Get module root directory (go up from Public folder)
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

        # Paths to system prompts
        $diagnosePromptPath = Join-Path -Path $moduleRoot -ChildPath 'DIAGNOSE.md'
        $diagnoseLogicPath = Join-Path -Path $moduleRoot -ChildPath 'DIAGNOSE_LOGIC.md'

        # Load system prompts
        if (-not (Test-Path $diagnosePromptPath)) {
            throw "DIAGNOSE.md not found at $diagnosePromptPath"
        }

        if (-not (Test-Path $diagnoseLogicPath)) {
            throw "DIAGNOSE_LOGIC.md not found at $diagnoseLogicPath"
        }

        Write-Verbose "Loading system prompts..."
        $diagnosePrompt = Get-Content -Path $diagnosePromptPath -Raw -Encoding UTF8
        $diagnoseLogic = Get-Content -Path $diagnoseLogicPath -Raw -Encoding UTF8

        # Combine into system prompt
        $systemPrompt = @"
$diagnosePrompt

## REASONING FRAMEWORK

$diagnoseLogic

## INSTRUCTIONS

You are analyzing a Windows PC hardware diagnostic report. Follow the reasoning framework above to:

1. Parse the diagnostic output into structured categories
2. Identify issues by severity (Critical, High, Medium, Low)
3. Apply the decision tree logic to determine root causes
4. Provide specific, actionable recommendations

Format your response with clear sections:
- Summary (2-4 bullet points)
- Findings by Category
- Priority Issues
- Recommended Next Steps

Be concise, technical, and safety-conscious. Warn about destructive operations.
"@

        Write-Verbose "System prompt loaded: $($systemPrompt.Length) characters"

        # Verify Ollama connectivity
        if (-not (Test-OllamaConnection)) {
            throw "Cannot connect to Ollama API. Ensure Ollama is running."
        }
    }

    process {
        # Load diagnostic report
        $diagnosticText = if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
            Write-Verbose "Loading diagnostic report from file: $DiagnosticReportPath"
            Get-Content -Path $DiagnosticReportPath -Raw -Encoding UTF8
        }
        else {
            Write-Verbose "Using diagnostic report from text parameter"
            $ReportText
        }

        if ([string]::IsNullOrWhiteSpace($diagnosticText)) {
            throw "Diagnostic report is empty or could not be read"
        }

        Write-Verbose "Diagnostic report loaded: $($diagnosticText.Length) characters"

        # Build user prompt
        $userPrompt = @"
Please analyze the following PC hardware diagnostic report:

```
$diagnosticText
```

Provide a comprehensive analysis with severity-based prioritization and actionable recommendations.
"@

        # Send to LLM
        Write-Host "Analyzing diagnostic report with $Model..." -ForegroundColor Cyan
        Write-Host "This may take 30-120 seconds depending on report size..." -ForegroundColor Gray

        $startTime = Get-Date

        try {
            $messages = @(
                @{
                    role = 'system'
                    content = $systemPrompt
                }
                @{
                    role = 'user'
                    content = $userPrompt
                }
            )

            $response = Invoke-OllamaChat -Messages $messages -Model $Model -Temperature $Temperature -TimeoutSeconds 180

            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds

            Write-Host "Analysis complete in $([math]::Round($duration, 1)) seconds" -ForegroundColor Green

            # Parse response
            $analysisText = $response.message.content

            # Build result object
            $result = [PSCustomObject]@{
                Analysis = $analysisText
                Model = $Model
                Temperature = $Temperature
                AnalysisDurationSeconds = [math]::Round($duration, 2)
                DiagnosticReportLength = $diagnosticText.Length
                ResponseLength = $analysisText.Length
                Timestamp = $startTime
                TokensEvaluated = $response.eval_count
            }

            if ($IncludeRawResponse) {
                $result | Add-Member -MemberType NoteProperty -Name 'RawResponse' -Value $response
            }

            # Save report if requested
            if ($SaveReport) {
                $reportContent = @"
PC DIAGNOSTICS ANALYSIS REPORT
Generated: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))
Model: $Model
Analysis Duration: $([math]::Round($duration, 2)) seconds

$("-" * 80)

$analysisText

$("-" * 80)

Analysis completed at $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))
"@

                $reportContent | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
                Write-Host "`nAnalysis report saved to: $OutputPath" -ForegroundColor Cyan

                $result | Add-Member -MemberType NoteProperty -Name 'ReportSavedTo' -Value $OutputPath
            }

            # Display analysis
            Write-Host "`n$("=" * 80)" -ForegroundColor Cyan
            Write-Host "PC DIAGNOSTICS ANALYSIS" -ForegroundColor Cyan
            Write-Host "$("=" * 80)`n" -ForegroundColor Cyan
            Write-Host $analysisText
            Write-Host "`n$("=" * 80)" -ForegroundColor Cyan

            return $result
        }
        catch {
            Write-Error "Diagnostic analysis failed: $_"
            throw
        }
    }

    end {
        Write-Verbose "PC diagnosis analysis completed"
    }
}
