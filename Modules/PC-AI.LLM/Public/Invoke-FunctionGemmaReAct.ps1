#Requires -Version 5.1
<#+
.SYNOPSIS
    Uses FunctionGemma (via vLLM OpenAI API) to plan tool calls and optionally executes them.

.DESCRIPTION
    Sends a prompt + tool schema to FunctionGemma and returns tool calls. When -ExecuteTools
    is specified, executes mapped PC_AI tools and optionally returns a final response from
    FunctionGemma after tool results are provided.
#>
function Invoke-FunctionGemmaReAct {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [string]$BaseUrl = 'http://127.0.0.1:8000',

        [Parameter()]
        [string]$Model = 'functiongemma-270m-it',

        [Parameter()]
        [string]$ToolsPath = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'Config\pcai-tools.json'),

        [Parameter()]
        [switch]$ExecuteTools,

        [Parameter()]
        [switch]$ReturnFinal,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxToolCalls = 3,

        [Parameter()]
        [ValidateRange(5, 600)]
        [int]$TimeoutSeconds = 120,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$ShowMetrics,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$ProgressIntervalSeconds = 1
    )

    if (-not (Test-Path $ToolsPath)) {
        throw "Tools config not found: $ToolsPath"
    }

    $tools = (Get-Content -Path $ToolsPath -Raw -Encoding UTF8 | ConvertFrom-Json).tools

    function Invoke-FunctionGemmaChat {
        param(
            [array]$Messages,
            [array]$Tools
        )
        $payload = @{
            model = $Model
            messages = $Messages
            tools = $Tools
            tool_choice = 'auto'
            temperature = 0.2
        }

        $uri = ("{0}/v1/chat/completions" -f $BaseUrl.TrimEnd('/'))
        $jsonBody = $payload | ConvertTo-Json -Depth 12
        $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

        if (-not $ShowProgress) {
            return Invoke-RestMethod -Method Post -Uri $uri -Body $jsonBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSeconds
        }

        $job = Start-Job -ScriptBlock {
            param($u, $bytes, $timeout)
            Invoke-RestMethod -Method Post -Uri $u -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec $timeout
        } -ArgumentList $uri, $jsonBytes, $TimeoutSeconds

        $modelInfo = Get-VLLMModelInfo -ApiUrl $BaseUrl -ModelName $Model
        $start = Get-Date
        while ($job.State -eq 'Running') {
            $elapsed = (Get-Date) - $start
            $metrics = Get-VLLMMetricsSnapshot -ApiUrl $BaseUrl -ModelName $Model -TimeoutSeconds 2
            $kv = if ($metrics) { "{0:P0}" -f $metrics.KVCacheUsagePerc } else { 'n/a' }
            $running = if ($metrics) { $metrics.NumRequestsRunning } else { 'n/a' }
            $waiting = if ($metrics) { $metrics.NumRequestsWaiting } else { 'n/a' }
            $context = if ($modelInfo -and $modelInfo.MaxModelLen) { $modelInfo.MaxModelLen } else { 'n/a' }

            $status = "Elapsed {0}s | KV {1} | Running {2} | Waiting {3} | MaxCtx {4}" -f `
                [int]$elapsed.TotalSeconds, $kv, $running, $waiting, $context
            Write-Progress -Activity "FunctionGemma request" -Status $status
            Start-Sleep -Seconds $ProgressIntervalSeconds
        }

        $resp = Receive-Job $job -ErrorAction Stop
        Remove-Job $job
        Write-Progress -Activity "FunctionGemma request" -Completed
        return $resp
    }

    function Invoke-ToolByName {
        param(
            [string]$Name,
            [hashtable]$Args
        )

        $toolDef = $tools | Where-Object { $_.function.name -eq $Name }
        if (-not $toolDef -or -not $toolDef.pcai_mapping) {
            return "Unhandled tool: $Name (no mapping found)"
        }

        $mapping = $toolDef.pcai_mapping

        # Dynamic Module Loading
        if ($mapping.module) {
            if (-not (Get-Module -Name $mapping.module -ListAvailable)) {
                $modulePath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "Modules\$($mapping.module)"
                Import-Module $modulePath -Force -ErrorAction SilentlyContinue
            }
        }

        # Parameter Binding
        if ($mapping.cmdlet -eq 'wsl') {
            $wslArgs = @()
            if ($mapping.args) { $wslArgs += $mapping.args }
            foreach ($key in $Args.Keys) {
                $wslArgs += $Args[$key]
            }
            & wsl @wslArgs | Out-Null
            return "WSL command executed: wsl $($wslArgs -join ' ')"
        }

        $params = @{}
        if ($mapping.params) {
            foreach ($pName in $mapping.params.psobject.Properties.Name) {
                $pValue = $mapping.params.$pName
                if ($pValue -match '^\$') {
                    $argKey = $pValue.TrimStart('$')
                    if ($Args.ContainsKey($argKey)) {
                        $params[$pName] = $Args[$argKey]
                    }
                } else {
                    $params[$pName] = $pValue
                }
            }
        }

        # Execute Cmdlet
        try {
            $cmdResult = & $mapping.cmdlet @params
            if ($cmdResult -is [PSCustomObject] -or $cmdResult -is [hashtable]) {
                return ($cmdResult | ConvertTo-Json -Depth 6)
            }
            return [string]$cmdResult
        } catch {
            return "Error executing tool $Name ($($mapping.cmdlet)): $($_.Exception.Message)"
        }
    }

    $messages = @(@{ role = 'user'; content = $Prompt })
    $metricsBefore = $null
    if ($ShowMetrics) {
        $metricsBefore = Get-VLLMMetricsSnapshot -ApiUrl $BaseUrl -ModelName $Model -TimeoutSeconds 3
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-FunctionGemmaChat -Messages $messages -Tools $tools
    $sw.Stop()
    $choice = $response.choices[0]
    $message = $choice.message

    $toolCalls = @()
    if ($message.tool_calls) {
        $toolCalls = $message.tool_calls
    }

    $toolResults = @()
    if ($ExecuteTools -and $toolCalls.Count -gt 0) {
        $callCount = 0
        foreach ($call in $toolCalls) {
            if ($callCount -ge $MaxToolCalls) { break }
            $callCount++
            $name = $call.function.name
            $args = $call.function.arguments
            if ($args -is [string]) {
                try { $args = $args | ConvertFrom-Json -ErrorAction Stop } catch { $args = @{} }
            }
            if (-not $args) { $args = @{} }
            $result = Invoke-ToolByName -Name $name -Args $args
            $toolResults += [PSCustomObject]@{
                name = $name
                arguments = $args
                result = $result
            }

            $messages += @{
                role = 'assistant'
                tool_calls = @($call)
            }
            $messages += @{
                role = 'tool'
                tool_call_id = $call.id
                content = [string]$result
            }
        }

        if ($ReturnFinal) {
            $final = Invoke-FunctionGemmaChat -Messages $messages -Tools $tools
            $finalMsg = $final.choices[0].message
            $metricsAfter = $null
            $metricsSummary = $null
            if ($ShowMetrics) {
                $metricsAfter = Get-VLLMMetricsSnapshot -ApiUrl $BaseUrl -ModelName $Model -TimeoutSeconds 3
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
                Prompt = $Prompt
                ToolCalls = $toolCalls
                ToolResults = $toolResults
                Response = $finalMsg.content
                RawResponse = $finalMsg
                Metrics = $metricsSummary
                Model = $Model
                BaseUrl = $BaseUrl
            }
        }
    }

    $metricsAfter = $null
    $metricsSummary = $null
    if ($ShowMetrics) {
        $metricsAfter = Get-VLLMMetricsSnapshot -ApiUrl $BaseUrl -ModelName $Model -TimeoutSeconds 3
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
        Prompt = $Prompt
        ToolCalls = $toolCalls
        ToolResults = $toolResults
        Response = $message.content
        RawResponse = $message
        Metrics = $metricsSummary
        Model = $Model
        BaseUrl = $BaseUrl
    }
}
