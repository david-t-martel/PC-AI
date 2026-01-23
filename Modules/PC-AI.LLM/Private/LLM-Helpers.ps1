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

    try {
        Write-Verbose "Sending request to Ollama: Model=$Model, Stream=$Stream"

        $response = Invoke-RestMethod -Uri "$ApiUrl/api/generate" `
            -Method Post `
            -Body $jsonBody `
            -ContentType 'application/json' `
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

    try {
        Write-Verbose "Sending chat request to Ollama: Model=$Model, Messages=$($Messages.Count)"

        $response = Invoke-RestMethod -Uri "$ApiUrl/api/chat" `
            -Method Post `
            -Body $jsonBody `
            -ContentType 'application/json' `
            -TimeoutSec $TimeoutSeconds `
            -ErrorAction Stop

        return $response
    }
    catch {
        Write-Error "Ollama chat API request failed: $_"
        throw
    }
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
