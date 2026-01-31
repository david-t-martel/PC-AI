#Requires -Version 7.0
<#
.SYNOPSIS
    PC-AI Inference Backend Evaluation Runner

.DESCRIPTION
    Comprehensive evaluation script for testing PC-AI inference backends:
    - pcai-inference (llama.cpp + mistral.rs)
    - HTTP/Ollama backends
    - A/B comparison between backends

.PARAMETER Backend
    Inference backend to evaluate: llamacpp, mistralrs, http, ollama, all

.PARAMETER ModelPath
    Path to GGUF model file (required for native backends)

.PARAMETER Dataset
    Evaluation dataset: diagnostic, general, safety, or path to custom JSON

.PARAMETER CreateBaseline
    Create a baseline snapshot with the given name

.PARAMETER CompareBaseline
    Compare against an existing baseline

.PARAMETER ABTest
    Run A/B test between two backends (e.g., "llamacpp:mistralrs")

.PARAMETER OutputPath
    Path to save evaluation results

.EXAMPLE
    .\Invoke-InferenceEvaluation.ps1 -Backend llamacpp -ModelPath "C:\models\llama-3.2-1b.gguf" -Dataset diagnostic

.EXAMPLE
    .\Invoke-InferenceEvaluation.ps1 -ABTest "llamacpp:mistralrs" -ModelPath "C:\models\model.gguf"

.EXAMPLE
    .\Invoke-InferenceEvaluation.ps1 -Backend llamacpp -CreateBaseline "v1.0.0-baseline"
#>
[CmdletBinding()]
param(
    [ValidateSet('llamacpp', 'mistralrs', 'http', 'ollama', 'all')]
    [string]$Backend = 'llamacpp',

    [string]$ModelPath,

    [string]$Dataset = 'diagnostic',

    [string]$CreateBaseline,

    [string]$CompareBaseline,

    [string]$ABTest,

    [string]$OutputPath,

    [int]$MaxTokens = 512,

    [float]$Temperature = 0.7,

    [int]$GpuLayers = -1,

    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# Import required modules
$scriptRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent $scriptRoot

Import-Module (Join-Path $projectRoot "Modules\PC-AI.Evaluation\PC-AI.Evaluation.psd1") -Force
Import-Module (Join-Path $projectRoot "Modules\PcaiInference.psm1") -Force -ErrorAction SilentlyContinue

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║            PC-AI Inference Evaluation Framework              ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

#region Helper Functions

function Write-Section {
    param([string]$Title)
    Write-Host "`n═══ $Title ═══" -ForegroundColor Yellow
}

function Format-Duration {
    param([timespan]$Duration)
    if ($Duration.TotalHours -ge 1) {
        return "{0:N0}h {1:N0}m {2:N0}s" -f $Duration.Hours, $Duration.Minutes, $Duration.Seconds
    } elseif ($Duration.TotalMinutes -ge 1) {
        return "{0:N0}m {1:N1}s" -f $Duration.Minutes, $Duration.Seconds
    } else {
        return "{0:N2}s" -f $Duration.TotalSeconds
    }
}

function Test-BackendAvailable {
    param([string]$Backend)

    switch ($Backend) {
        { $_ -in 'llamacpp', 'mistralrs' } {
            # Check if DLL is available
            $dllPath = Join-Path $projectRoot "bin\Release\pcai_inference.dll"
            if (-not (Test-Path $dllPath)) {
                $dllPath = Join-Path $env:CARGO_TARGET_DIR "release\pcai_inference.dll" -ErrorAction SilentlyContinue
            }
            return Test-Path $dllPath
        }
        'http' {
            try {
                $null = Invoke-RestMethod -Uri "http://127.0.0.1:8080/health" -TimeoutSec 2
                return $true
            } catch { return $false }
        }
        'ollama' {
            try {
                $null = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 2
                return $true
            } catch { return $false }
        }
    }
    return $false
}

#endregion

#region Main Evaluation Logic

function Invoke-BackendEvaluation {
    param(
        [string]$Backend,
        [string]$ModelPath,
        [string]$Dataset,
        [int]$MaxTokens,
        [float]$Temperature,
        [int]$GpuLayers
    )

    Write-Section "Evaluating Backend: $Backend"

    # Check availability
    if (-not (Test-BackendAvailable -Backend $Backend)) {
        Write-Warning "Backend '$Backend' is not available. Skipping."
        return $null
    }

    # Create evaluation suite
    $suite = New-EvaluationSuite -Name "PC-AI-$Backend-Eval" `
        -Description "Evaluation of $Backend backend for PC-AI diagnostics" `
        -Metrics @('latency', 'throughput', 'similarity', 'coherence') `
        -IncludeDefaultMetrics

    # Load test cases
    $testCases = Get-EvaluationDataset -Name $Dataset
    if (-not $testCases) {
        Write-Error "Failed to load dataset: $Dataset"
        return $null
    }

    Write-Host "  Loaded $($testCases.Count) test cases from '$Dataset'" -ForegroundColor Gray

    # Add test cases to suite
    foreach ($tc in $testCases) {
        $suite.AddTestCase($tc)
    }

    # Run evaluation
    $results = Invoke-EvaluationSuite -Suite $suite `
        -Backend $Backend `
        -ModelPath $ModelPath `
        -MaxTokens $MaxTokens `
        -Temperature $Temperature `
        -GpuLayers $GpuLayers

    return @{
        Backend = $Backend
        Suite = $suite
        Results = $results
    }
}

function Invoke-ABTestEvaluation {
    param(
        [string]$VariantSpec,
        [string]$ModelPath,
        [string]$Dataset,
        [int]$MaxTokens,
        [float]$Temperature
    )

    $variants = $VariantSpec -split ':'
    if ($variants.Count -ne 2) {
        Write-Error "A/B test requires two variants in format 'backendA:backendB'"
        return
    }

    $variantA, $variantB = $variants

    Write-Section "A/B Test: $variantA vs $variantB"

    # Check both backends available
    foreach ($v in $variants) {
        if (-not (Test-BackendAvailable -Backend $v)) {
            Write-Error "Backend '$v' is not available for A/B test"
            return
        }
    }

    # Create A/B test
    $abTest = New-ABTest -Name "pcai-ab-$variantA-vs-$variantB" `
        -VariantAName $variantA `
        -VariantBName $variantB

    # Load test cases
    $testCases = Get-EvaluationDataset -Name $Dataset

    Write-Host "  Running $($testCases.Count) test cases on both variants..." -ForegroundColor Gray

    foreach ($tc in $testCases) {
        Write-Host "    Testing: $($tc.Id)" -ForegroundColor DarkGray

        # Test Variant A
        try {
            $initA = Initialize-PcaiInference -Backend $variantA
            if ($ModelPath) { $null = Import-PcaiModel -ModelPath $ModelPath }

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $responseA = Invoke-PcaiGenerate -Prompt $tc.Prompt -MaxTokens $MaxTokens -Temperature $Temperature
            $sw.Stop()

            $scoreA = if ($tc.ExpectedOutput) {
                Compare-ResponseSimilarity -Response $responseA -Expected $tc.ExpectedOutput
            } else {
                Measure-Coherence -Response $responseA
            }

            Add-ABTestResult -TestName $abTest.Name -Variant "A" -Score $scoreA
            Close-PcaiInference
        } catch {
            Write-Warning "Variant A failed on $($tc.Id): $_"
        }

        # Test Variant B
        try {
            $initB = Initialize-PcaiInference -Backend $variantB
            if ($ModelPath) { $null = Import-PcaiModel -ModelPath $ModelPath }

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $responseB = Invoke-PcaiGenerate -Prompt $tc.Prompt -MaxTokens $MaxTokens -Temperature $Temperature
            $sw.Stop()

            $scoreB = if ($tc.ExpectedOutput) {
                Compare-ResponseSimilarity -Response $responseB -Expected $tc.ExpectedOutput
            } else {
                Measure-Coherence -Response $responseB
            }

            Add-ABTestResult -TestName $abTest.Name -Variant "B" -Score $scoreB
            Close-PcaiInference
        } catch {
            Write-Warning "Variant B failed on $($tc.Id): $_"
        }
    }

    # Analyze results
    $analysis = Get-ABTestAnalysis -TestName $abTest.Name

    return $analysis
}

#endregion

#region Main Execution

$startTime = [datetime]::UtcNow
$allResults = @{}

try {
    # A/B Test Mode
    if ($ABTest) {
        $abResults = Invoke-ABTestEvaluation -VariantSpec $ABTest `
            -ModelPath $ModelPath `
            -Dataset $Dataset `
            -MaxTokens $MaxTokens `
            -Temperature $Temperature

        $allResults['ABTest'] = $abResults
    }
    # Single/Multi Backend Mode
    else {
        $backends = if ($Backend -eq 'all') {
            @('llamacpp', 'mistralrs', 'http', 'ollama')
        } else {
            @($Backend)
        }

        foreach ($be in $backends) {
            $evalResult = Invoke-BackendEvaluation -Backend $be `
                -ModelPath $ModelPath `
                -Dataset $Dataset `
                -MaxTokens $MaxTokens `
                -Temperature $Temperature `
                -GpuLayers $GpuLayers

            if ($evalResult) {
                $allResults[$be] = $evalResult

                # Create baseline if requested
                if ($CreateBaseline -and $evalResult.Suite) {
                    Write-Section "Creating Baseline: $CreateBaseline"
                    $baseline = New-BaselineSnapshot -Name "$CreateBaseline-$be" `
                        -Suite $evalResult.Suite `
                        -Backend $be `
                        -ModelPath $ModelPath
                }

                # Compare to baseline if requested
                if ($CompareBaseline -and $evalResult.Suite) {
                    Write-Section "Comparing to Baseline: $CompareBaseline"
                    $regression = Test-ForRegression -BaselineName "$CompareBaseline-$be" `
                        -Suite $evalResult.Suite
                    $allResults["${be}_regression"] = $regression
                }
            }
        }
    }

    # Generate summary
    $endTime = [datetime]::UtcNow
    $totalDuration = $endTime - $startTime

    Write-Section "Evaluation Summary"

    foreach ($key in $allResults.Keys) {
        $result = $allResults[$key]

        if ($result.Results) {
            Write-Host "`n  $key`:" -ForegroundColor White
            Write-Host "    Pass Rate: $($result.Results.PassRate)%"
            Write-Host "    Avg Score: $($result.Results.AverageScore)"
            Write-Host "    Avg Latency: $([math]::Round($result.Results.AverageLatency, 2))ms"
        } elseif ($result.Winner) {
            Write-Host "`n  A/B Test Result:" -ForegroundColor White
            Write-Host "    Winner: $($result.Winner)"
            Write-Host "    Effect Size: $($result.EffectSize) (d=$($result.CohensD))"
            Write-Host "    Significant: $($result.StatisticallySignificant)"
        }
    }

    Write-Host "`n  Total Duration: $(Format-Duration $totalDuration)" -ForegroundColor Gray

    # Save results if output path specified
    if ($OutputPath) {
        $outputDir = Split-Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        $exportData = @{
            Timestamp = $startTime.ToString('o')
            Duration = $totalDuration.ToString()
            Parameters = @{
                Backend = $Backend
                ModelPath = $ModelPath
                Dataset = $Dataset
                MaxTokens = $MaxTokens
                Temperature = $Temperature
            }
            Results = $allResults | ForEach-Object {
                @{
                    Key = $_.Key
                    Value = if ($_.Value.Results) { $_.Value.Results } else { $_.Value }
                }
            }
        }

        $exportData | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath
        Write-Host "`n  Results saved: $OutputPath" -ForegroundColor Green
    }

} catch {
    Write-Error "Evaluation failed: $_"
    throw
}

#endregion

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    Evaluation Complete                       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
