#Requires -Version 5.1

<#
.SYNOPSIS
    Private helper functions for LLM API operations
#>

function Test-OllamaConnection {
    <#
    .SYNOPSIS
        Tests connectivity to Ollama API
    .OUTPUTS
        Boolean indicating connection status
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string]$ApiUrl = $script:ModuleConfig.OllamaApiUrl,

        [Parameter()]
        [int]$TimeoutSeconds = 5
    )

    try {
        $response = Invoke-RestMethod -Uri "$ApiUrl/api/tags" -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        return $true
    }
    catch {
        Write-Verbose "Ollama connection test failed: $_"
        return $false
    }
}

function Test-LMStudioConnection {
    <#
    .SYNOPSIS
        Tests connectivity to LM Studio API
    .OUTPUTS
        Boolean indicating connection status
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string]$ApiUrl = $script:ModuleConfig.LMStudioApiUrl,

        [Parameter()]
        [int]$TimeoutSeconds = 5
    )

    try {
        $response = Invoke-RestMethod -Uri "$ApiUrl/v1/models" -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        return $true
    }
    catch {
        Write-Verbose "LM Studio connection test failed: $_"
        return $false
    }
}

function Test-OpenAIConnection {
    <#
    .SYNOPSIS
        Tests connectivity to an OpenAI-compatible API (vLLM/LM Studio)
    .OUTPUTS
        Boolean indicating connection status
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ApiUrl,

        [Parameter()]
        [int]$TimeoutSeconds = 5
    )

    try {
        $response = Invoke-RestMethod -Uri "$ApiUrl/v1/models" -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        return $true
    }
    catch {
        Write-Verbose "OpenAI-compatible connection test failed: $_"
        return $false
    }
}

function Get-VLLMModelInfo {
    <#
    .SYNOPSIS
        Retrieves model metadata from a vLLM OpenAI-compatible endpoint.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ApiUrl = $script:ModuleConfig.VLLMApiUrl,

        [Parameter()]
        [string]$ModelName = $script:ModuleConfig.VLLMModel,

        [Parameter()]
        [int]$TimeoutSeconds = 5
    )

    try {
        $resp = Invoke-RestMethod -Uri "$ApiUrl/v1/models" -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        $model = $null
        if ($resp.data) {
            $model = $resp.data | Where-Object { $_.id -eq $ModelName } | Select-Object -First 1
            if (-not $model) { $model = $resp.data | Select-Object -First 1 }
        }

        if (-not $model) { return $null }

        return [PSCustomObject]@{
            Id          = $model.id
            MaxModelLen = $model.max_model_len
            Root        = $model.root
            OwnedBy     = $model.owned_by
        }
    }
    catch {
        Write-Verbose "Failed to get vLLM model info: $_"
        return $null
    }
}

function Get-VLLMMetricsSnapshot {
    <#
    .SYNOPSIS
        Fetches and parses vLLM /metrics for lightweight health/throughput data.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ApiUrl = $script:ModuleConfig.VLLMApiUrl,

        [Parameter()]
        [string]$ModelName = $script:ModuleConfig.VLLMModel,

        [Parameter()]
        [int]$TimeoutSeconds = 5
    )

    try {
        $metricsText = Invoke-RestMethod -Uri "$ApiUrl/metrics" -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
    }
    catch {
        Write-Verbose "Failed to fetch vLLM metrics: $_"
        return $null
    }

    $values = @{
        PromptTokensTotal     = 0.0
        GenerationTokensTotal = 0.0
        RequestSuccessTotal   = 0.0
        NumRequestsRunning    = 0.0
        NumRequestsWaiting    = 0.0
        KVCacheUsagePerc      = 0.0
    }

    foreach ($line in ($metricsText -split "`n")) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $m = [regex]::Match($line, '^(?<metric>vllm:[^\\s{]+)(?<labels>{[^}]+})?\\s+(?<value>[-+0-9.eE]+)$')
        if (-not $m.Success) { continue }

        $metric = $m.Groups['metric'].Value
        $value = [double]$m.Groups['value'].Value
        $labels = $m.Groups['labels'].Value
        if ($labels) {
            $labels = $labels.Trim('{', '}')
            $modelMatch = [regex]::Match($labels, 'model_name=\"(?<name>[^\"]+)\"')
            if ($modelMatch.Success -and $ModelName -and $modelMatch.Groups['name'].Value -ne $ModelName) {
                continue
            }
        }

        switch ($metric) {
            'vllm:prompt_tokens_total' { $values.PromptTokensTotal = $value }
            'vllm:generation_tokens_total' { $values.GenerationTokensTotal = $value }
            'vllm:request_success_total' { $values.RequestSuccessTotal += $value }
            'vllm:num_requests_running' { $values.NumRequestsRunning = $value }
            'vllm:num_requests_waiting' { $values.NumRequestsWaiting = $value }
            'vllm:kv_cache_usage_perc' { $values.KVCacheUsagePerc = $value }
        }
    }

    return [PSCustomObject]@{
        CapturedAt            = Get-Date
        ModelName             = $ModelName
        ApiUrl                = $ApiUrl
        PromptTokensTotal     = [double]$values.PromptTokensTotal
        GenerationTokensTotal = [double]$values.GenerationTokensTotal
        RequestSuccessTotal   = [double]$values.RequestSuccessTotal
        NumRequestsRunning    = [double]$values.NumRequestsRunning
        NumRequestsWaiting    = [double]$values.NumRequestsWaiting
        KVCacheUsagePerc      = [double]$values.KVCacheUsagePerc
        TokensTotal           = [double]$values.PromptTokensTotal + [double]$values.GenerationTokensTotal
    }
}

function Invoke-OpenAIChatWithProgress {
    <#
    .SYNOPSIS
        Invokes OpenAI-compatible chat completion with a progress display and vLLM metrics.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [array]$Messages,

        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature = 0.7,

        [Parameter()]
        [int]$MaxTokens,

        [Parameter()]
        [int]$TimeoutSeconds = $script:ModuleConfig.DefaultTimeout,

        [Parameter(Mandatory)]
        [string]$ApiUrl,

        [Parameter()]
        [string]$ApiKey,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$ProgressIntervalSeconds = 1
    )

    $body = @{
        model = $Model
        messages = $Messages
        temperature = $Temperature
        stream = $false
    }
    if ($MaxTokens) { $body['max_tokens'] = $MaxTokens }

    $jsonBody = $body | ConvertTo-Json -Depth 10
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    $headers = @{}
    if ($ApiKey) { $headers['Authorization'] = "Bearer $ApiKey" }

    $uri = "$ApiUrl/v1/chat/completions"
    $job = Start-Job -ScriptBlock {
        param($u, $bytes, $hdrs, $timeout)
        Invoke-RestMethod -Uri $u -Method Post -Body $bytes -Headers $hdrs -ContentType 'application/json; charset=utf-8' -TimeoutSec $timeout
    } -ArgumentList $uri, $jsonBytes, $headers, $TimeoutSeconds

    $modelInfo = Get-VLLMModelInfo -ApiUrl $ApiUrl -ModelName $Model
    $start = Get-Date
    while ($job.State -eq 'Running') {
        $elapsed = (Get-Date) - $start
        $metrics = Get-VLLMMetricsSnapshot -ApiUrl $ApiUrl -ModelName $Model -TimeoutSeconds 2
        $kv = if ($metrics) { "{0:P0}" -f $metrics.KVCacheUsagePerc } else { 'n/a' }
        $running = if ($metrics) { $metrics.NumRequestsRunning } else { 'n/a' }
        $waiting = if ($metrics) { $metrics.NumRequestsWaiting } else { 'n/a' }
        $context = if ($modelInfo -and $modelInfo.MaxModelLen) { $modelInfo.MaxModelLen } else { 'n/a' }

        $status = "Elapsed {0}s | KV {1} | Running {2} | Waiting {3} | MaxCtx {4}" -f `
            [int]$elapsed.TotalSeconds, $kv, $running, $waiting, $context
        Write-Progress -Activity "vLLM request" -Status $status
        Start-Sleep -Seconds $ProgressIntervalSeconds
    }

    $response = Receive-Job $job -ErrorAction Stop
    Remove-Job $job
    Write-Progress -Activity "vLLM request" -Completed

    $content = $null
    if ($response.choices -and $response.choices.Count -gt 0) {
        $content = $response.choices[0].message.content
    }

    return [PSCustomObject]@{
        message = [PSCustomObject]@{ content = $content }
        provider = 'openai'
        raw = $response
    }
}

function Get-OllamaModels {
    <#
    .SYNOPSIS
        Retrieves list of available Ollama models
    .OUTPUTS
        Array of model objects
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [string]$ApiUrl = $script:ModuleConfig.OllamaApiUrl
    )

    try {
        $response = Invoke-RestMethod -Uri "$ApiUrl/api/tags" -Method Get -ErrorAction Stop

        if ($response.models) {
            return $response.models | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    ModifiedAt = $_.modified_at
                    Size = $_.size
                    Digest = $_.digest
                    Details = $_.details
                }
            }
        }
        else {
            return @()
        }
    }
    catch {
        Write-Error "Failed to retrieve Ollama models: $_"
        return @()
    }
}

function Invoke-OllamaGenerate {
    <#
    .SYNOPSIS
        Invokes Ollama generate API endpoint
    .OUTPUTS
        API response object
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [string]$Model = $script:ModuleConfig.DefaultModel,

        [Parameter()]
        [string]$System,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature = 0.7,

        [Parameter()]
        [int]$MaxTokens,

        [Parameter()]
        [bool]$Stream = $false,

        [Parameter()]
        [int]$TimeoutSeconds = $script:ModuleConfig.DefaultTimeout,

        [Parameter()]
        [string]$ApiUrl = $script:ModuleConfig.OllamaApiUrl
    )

    $body = @{
        model = $Model
        prompt = $Prompt
        stream = $Stream
        options = @{
            temperature = $Temperature
        }
    }

    if ($System) {
        $body['system'] = $System
    }

    if ($MaxTokens) {
        $body.options['num_predict'] = $MaxTokens
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10
    # Force UTF-8 (no BOM) to avoid Ollama JSON parse errors in some hosts
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    try {
        Write-Verbose "Sending request to Ollama: Model=$Model, Stream=$Stream"

        $response = Invoke-RestMethod -Uri "$ApiUrl/api/generate" `
            -Method Post `
            -Body $jsonBytes `
            -ContentType 'application/json; charset=utf-8' `
            -TimeoutSec $TimeoutSeconds `
            -ErrorAction Stop

        return $response
    }
    catch {
        Write-Error "Ollama API request failed: $_"
        throw
    }
}

function Invoke-OllamaChat {
    <#
    .SYNOPSIS
        Invokes Ollama chat API endpoint
    .OUTPUTS
        API response object
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [array]$Messages,

        [Parameter()]
        [string]$Model = $script:ModuleConfig.DefaultModel,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature = 0.7,

        [Parameter()]
        [int]$MaxTokens,

        [Parameter()]
        [bool]$Stream = $false,

        [Parameter()]
        [int]$TimeoutSeconds = $script:ModuleConfig.DefaultTimeout,

        [Parameter()]
        [string]$ApiUrl = $script:ModuleConfig.OllamaApiUrl
    )

    $body = @{
        model = $Model
        messages = $Messages
        stream = $Stream
        options = @{
            temperature = $Temperature
        }
    }

    if ($MaxTokens) {
        $body.options['num_predict'] = $MaxTokens
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10
    # Force UTF-8 (no BOM) to avoid Ollama JSON parse errors in some hosts
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    try {
        Write-Verbose "Sending chat request to Ollama: Model=$Model, Messages=$($Messages.Count)"

        $response = Invoke-RestMethod -Uri "$ApiUrl/api/chat" `
            -Method Post `
            -Body $jsonBytes `
            -ContentType 'application/json; charset=utf-8' `
            -TimeoutSec $TimeoutSeconds `
            -ErrorAction Stop

        return $response
    }
    catch {
        Write-Error "Ollama chat API request failed: $_"
        throw
    }
}

function Invoke-OpenAIChat {
    <#
    .SYNOPSIS
        Invokes an OpenAI-compatible chat completion endpoint (vLLM/LM Studio)
    .OUTPUTS
        PSCustomObject normalized to include message.content
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [array]$Messages,

        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature = 0.7,

        [Parameter()]
        [int]$MaxTokens,

        [Parameter()]
        [int]$TimeoutSeconds = $script:ModuleConfig.DefaultTimeout,

        [Parameter(Mandatory)]
        [string]$ApiUrl,

        [Parameter()]
        [string]$ApiKey
    )

    $body = @{
        model = $Model
        messages = $Messages
        temperature = $Temperature
        stream = $false
    }

    if ($MaxTokens) {
        $body['max_tokens'] = $MaxTokens
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    $headers = @{}
    if ($ApiKey) {
        $headers['Authorization'] = "Bearer $ApiKey"
    }

    try {
        $response = Invoke-RestMethod -Uri "$ApiUrl/v1/chat/completions" `
            -Method Post `
            -Body $jsonBytes `
            -Headers $headers `
            -ContentType 'application/json; charset=utf-8' `
            -TimeoutSec $TimeoutSeconds `
            -ErrorAction Stop

        $content = $null
        if ($response.choices -and $response.choices.Count -gt 0) {
            $content = $response.choices[0].message.content
        }

        return [PSCustomObject]@{
            message = [PSCustomObject]@{
                content = $content
            }
            provider = 'openai'
            raw = $response
        }
    }
    catch {
        Write-Error "OpenAI-compatible chat request failed: $_"
        throw
    }
}

function Invoke-LLMChatWithFallback {
    <#
    .SYNOPSIS
        Invokes LLM chat with provider fallback order.
    .OUTPUTS
        PSCustomObject normalized to include message.content and provider
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [array]$Messages,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature = 0.7,

        [Parameter()]
        [int]$MaxTokens,

        [Parameter()]
        [int]$TimeoutSeconds = $script:ModuleConfig.DefaultTimeout,

        [Parameter()]
        [ValidateSet('auto','ollama','vllm','lmstudio')]
        [string]$Provider = 'auto',

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$ProgressIntervalSeconds = 1
    )

    $providers = if ($Provider -eq 'auto') {
        if ($script:ModuleConfig.ProviderOrder) { @($script:ModuleConfig.ProviderOrder) } else { @('ollama','vllm','lmstudio') }
    } else {
        @($Provider)
    }

    foreach ($p in $providers) {
        switch ($p) {
            'ollama' {
                if (Test-OllamaConnection) {
                    $modelToUse = if ($Model) { $Model } else { $script:ModuleConfig.DefaultModel }
                    $resp = Invoke-OllamaChat -Messages $Messages -Model $modelToUse -Temperature $Temperature -MaxTokens $MaxTokens -TimeoutSeconds $TimeoutSeconds
                    $resp | Add-Member -MemberType NoteProperty -Name Provider -Value 'ollama' -Force
                    return $resp
                }
            }
            'vllm' {
                if (Test-OpenAIConnection -ApiUrl $script:ModuleConfig.VLLMApiUrl) {
                    if ($Model -and $Model -ne $script:ModuleConfig.DefaultModel) {
                        $modelToUse = $Model
                    } else {
                        $modelToUse = $script:ModuleConfig.VLLMModel
                    }
                    if ($ShowProgress) {
                        $resp = Invoke-OpenAIChatWithProgress -Messages $Messages -Model $modelToUse -Temperature $Temperature -MaxTokens $MaxTokens -TimeoutSeconds $TimeoutSeconds -ApiUrl $script:ModuleConfig.VLLMApiUrl -ProgressIntervalSeconds $ProgressIntervalSeconds
                    } else {
                        $resp = Invoke-OpenAIChat -Messages $Messages -Model $modelToUse -Temperature $Temperature -MaxTokens $MaxTokens -TimeoutSeconds $TimeoutSeconds -ApiUrl $script:ModuleConfig.VLLMApiUrl
                    }
                    $resp | Add-Member -MemberType NoteProperty -Name Provider -Value 'vllm' -Force
                    return $resp
                }
            }
            'lmstudio' {
                if (Test-OpenAIConnection -ApiUrl $script:ModuleConfig.LMStudioApiUrl) {
                    $modelToUse = if ($Model) { $Model } else { $script:ModuleConfig.DefaultModel }
                    $resp = Invoke-OpenAIChat -Messages $Messages -Model $modelToUse -Temperature $Temperature -MaxTokens $MaxTokens -TimeoutSeconds $TimeoutSeconds -ApiUrl $script:ModuleConfig.LMStudioApiUrl
                    $resp | Add-Member -MemberType NoteProperty -Name Provider -Value 'lmstudio' -Force
                    return $resp
                }
            }
        }
    }

    throw 'No LLM providers are reachable in the configured fallback order.'
}

function Format-TokenCount {
    <#
    .SYNOPSIS
        Formats byte size to human-readable format
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes bytes"
    }
}

function Get-ServiceStatus {
    <#
    .SYNOPSIS
        Gets the status of a Windows service by name
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        if ($service) {
            return [PSCustomObject]@{
                Name = $service.Name
                DisplayName = $service.DisplayName
                Status = $service.Status.ToString()
                StartType = $service.StartType.ToString()
                Running = ($service.Status -eq 'Running')
            }
        }
        else {
            return [PSCustomObject]@{
                Name = $ServiceName
                DisplayName = 'Not Found'
                Status = 'NotInstalled'
                StartType = 'Unknown'
                Running = $false
            }
        }
    }
    catch {
        Write-Warning "Failed to get service status for $ServiceName`: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Name = $ServiceName
            DisplayName = 'Error'
            Status = 'Error'
            StartType = 'Unknown'
            Running = $false
        }
    }
}
