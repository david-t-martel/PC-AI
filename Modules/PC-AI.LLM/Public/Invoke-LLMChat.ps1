#Requires -Version 5.1

function Invoke-LLMChat {
    <#
    .SYNOPSIS
        Interactive chat interface with Ollama LLM
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [string]$Message,

        [Parameter()]
        [string]$Model = $script:ModuleConfig.DefaultModel,

        [Parameter()]
        [string]$System,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature = 0.7,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [int]$MaxTokens,

        [Parameter()]
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = $script:ModuleConfig.DefaultTimeout,

        [Parameter()]
        [switch]$Interactive,

        [Parameter()]
        [switch]$ToJson,

        [Parameter()]
        [array]$History = @(),

        [Parameter()]
        [ValidateSet('auto', 'ollama', 'vllm', 'lmstudio')]
        [string]$Provider = 'auto',

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$ShowMetrics,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$ProgressIntervalSeconds = 1
    )

    begin {
        $conversationHistory = [System.Collections.ArrayList]::new()
        if ($System) { [void]$conversationHistory.Add(@{ role = 'system'; content = $System }) }
        foreach ($msg in $History) { [void]$conversationHistory.Add($msg) }
    }

    process {
        if ($Interactive) {
            Write-Host "`nStarting interactive chat session with $Model" -ForegroundColor Cyan
            $continueChat = $true
            while ($continueChat) {
                Write-Host "`nYou: " -NoNewline -ForegroundColor Green
                $userInput = Read-Host

                switch ($userInput.ToLower().Trim()) {
                    { $_ -in @('exit', 'quit', 'q') } { $continueChat = $false; break }
                    'clear' {
                        $conversationHistory.Clear()
                        if ($System) { [void]$conversationHistory.Add(@{ role = 'system'; content = $System }) }
                        continue
                    }
                }

                if ([string]::IsNullOrWhiteSpace($userInput)) { continue }

                [void]$conversationHistory.Add(@{ role = 'user'; content = $userInput })

                # ReAct Tool Loop
                $toolCallLimit = 3
                $toolCallCount = 0
                $processingResponse = $true

                while ($processingResponse -and $toolCallCount -lt $toolCallLimit) {
                    try {
                        $metricsBefore = $null
                        if ($ShowMetrics) {
                            $metricsBefore = Get-VLLMMetricsSnapshot -ApiUrl $script:ModuleConfig.VLLMApiUrl -ModelName $script:ModuleConfig.VLLMModel -TimeoutSeconds 3
                        }

                        $sw = [System.Diagnostics.Stopwatch]::StartNew()
                        $params = @{
                            Messages       = $conversationHistory.ToArray()
                            Model          = $Model
                            Temperature    = $Temperature
                            TimeoutSeconds = $TimeoutSeconds
                            Provider       = $Provider
                            ShowProgress   = $ShowProgress
                            ProgressIntervalSeconds = $ProgressIntervalSeconds
                        }
                        if ($PSBoundParameters.ContainsKey('MaxTokens')) { $params['MaxTokens'] = $MaxTokens }

                        $response = Invoke-LLMChatWithFallback @params
                        $sw.Stop()
                        $metricsAfter = $null
                        if ($ShowMetrics -and $response.Provider -eq 'vllm') {
                            $metricsAfter = Get-VLLMMetricsSnapshot -ApiUrl $script:ModuleConfig.VLLMApiUrl -ModelName $script:ModuleConfig.VLLMModel -TimeoutSeconds 3
                        }
                        $assistantMessage = $response.message.content
                        [void]$conversationHistory.Add(@{ role = 'assistant'; content = $assistantMessage })

                        # Parse for tool calls (Simplified with helper or standard pattern)
                        $toolPattern = '(?s)callTool\((?<name>[^,]+),\s*(?<args>.*?)\)'
                        if ($assistantMessage -match $toolPattern) {
                            $toolName = $Matches['name'].Trim()
                            $toolArgs = $Matches['args'].Trim()
                            $toolCallCount++

                            Write-Host "`n[Tool Call] Executing $toolName..." -ForegroundColor Yellow
                            $toolResult = 'Error: Tool failed'
                            try {
                                switch ($toolName) {
                                    'SearchDocs' {
                                        if ($toolArgs -match "'(?<query>.*?)'(\s*,\s*'(?<source>.*?)')?") {
                                            $source = if ($Matches['source']) { $Matches['source'] } else { 'Microsoft' }
                                            $toolResult = Invoke-DocSearch -Query $Matches['query'] -Source $source
                                        }
                                    }
                                    'GetSystemInfo' {
                                        if ($toolArgs -match "'(?<cat>.*?)'(\s*,\s*'(?<det>.*?)')?") {
                                            $detail = if ($Matches['det']) { $Matches['det'] } else { 'Summary' }
                                            $toolResult = Get-SystemInfoTool -Category $Matches['cat'] -Detail $detail
                                        }
                                    }
                                }
                            } catch { $toolResult = "Error: $($_.Exception.Message)" }

                            [void]$conversationHistory.Add(@{ role = 'user'; content = "TOOL_RESULT($toolName): $toolResult" })
                        } else {
                            Write-Host "`nAssistant: $assistantMessage" -ForegroundColor Blue
                            if ($ShowMetrics -and $metricsBefore -and $metricsAfter) {
                                $promptDelta = $metricsAfter.PromptTokensTotal - $metricsBefore.PromptTokensTotal
                                $genDelta = $metricsAfter.GenerationTokensTotal - $metricsBefore.GenerationTokensTotal
                                $tps = 0
                                if ($sw.Elapsed.TotalSeconds -gt 0) {
                                    $tps = ($promptDelta + $genDelta) / $sw.Elapsed.TotalSeconds
                                }
                                Write-Host ("vLLM metrics: {0:N0} prompt, {1:N0} gen tokens, {2:N2} tok/s, KV {3:P0}" -f $promptDelta, $genDelta, $tps, $metricsAfter.KVCacheUsagePerc) -ForegroundColor DarkGray
                            }
                            $processingResponse = $false
                        }
                    } catch { $processingResponse = $false }
                }
            }
        } else {
            # Single-shot mode
            [void]$conversationHistory.Add(@{ role = 'user'; content = $Message })
            $metricsBefore = $null
            if ($ShowMetrics) {
                $metricsBefore = Get-VLLMMetricsSnapshot -ApiUrl $script:ModuleConfig.VLLMApiUrl -ModelName $script:ModuleConfig.VLLMModel -TimeoutSeconds 3
            }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $params = @{
                Messages       = $conversationHistory.ToArray()
                Model          = $Model
                Temperature    = $Temperature
                TimeoutSeconds = $TimeoutSeconds
                Provider       = $Provider
                ShowProgress   = $ShowProgress
                ProgressIntervalSeconds = $ProgressIntervalSeconds
            }
            if ($PSBoundParameters.ContainsKey('MaxTokens')) { $params['MaxTokens'] = $MaxTokens }

            $response = Invoke-LLMChatWithFallback @params
            $sw.Stop()
            $assistantMessage = $response.message.content
            [void]$conversationHistory.Add(@{ role = 'assistant'; content = $assistantMessage })

            $finalResponse = $assistantMessage
            if ($ToJson) {
                # Utilize Natively-accelerated JSON extractor
                $finalResponse = ConvertFrom-LLMJson -Content $assistantMessage
            }

            $metricsAfter = $null
            $metricsSummary = $null
            if ($ShowMetrics -and $response.Provider -eq 'vllm') {
                $metricsAfter = Get-VLLMMetricsSnapshot -ApiUrl $script:ModuleConfig.VLLMApiUrl -ModelName $script:ModuleConfig.VLLMModel -TimeoutSeconds 3
                if ($metricsBefore -and $metricsAfter) {
                    $promptDelta = $metricsAfter.PromptTokensTotal - $metricsBefore.PromptTokensTotal
                    $genDelta = $metricsAfter.GenerationTokensTotal - $metricsBefore.GenerationTokensTotal
                    $tps = 0
                    if ($sw.Elapsed.TotalSeconds -gt 0) {
                        $tps = ($promptDelta + $genDelta) / $sw.Elapsed.TotalSeconds
                    }
                    $metricsSummary = [PSCustomObject]@{
                        ElapsedSeconds   = [math]::Round($sw.Elapsed.TotalSeconds, 3)
                        PromptTokens     = [int]$promptDelta
                        GenerationTokens = [int]$genDelta
                        TokensPerSecond  = [math]::Round($tps, 2)
                        KVCacheUsagePerc = $metricsAfter.KVCacheUsagePerc
                    }
                }
            }

            return [PSCustomObject]@{
                Response      = $finalResponse
                RawResponse   = $assistantMessage
                Model         = $Model
                History       = $conversationHistory.ToArray()
                TotalDuration = $response.total_duration
                Metrics       = $metricsSummary
                Timestamp     = Get-Date
            }
        }
    }
}
