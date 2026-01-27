#Requires -Version 5.1

<#
.SYNOPSIS
    Extracts and parses JSON from LLM responses, prioritizing native performance.
#>
function ConvertFrom-LLMJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Content,

        [Parameter()]
        [switch]$Strict
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Content)) { return $null }

        $jsonStr = $null

        # 1. Try Native Extraction (Highest Performance)
        # We try to use the direct FFI bridge if available
        if ([PcaiNative.PcaiCore]::IsAvailable) {
            try {
                $jsonStr = [PcaiNative.PcaiCore]::ExtractJson($Content)
                Write-Verbose 'Natively extracted JSON'
            } catch {
                Write-Verbose "Native JSON extraction failed: $_"
            }
        }

        # 2. PowerShell Fallback (Regex-based)
        if (-not $jsonStr) {
            if ($Content -match '(?s)```json\s*(?<json>.*?)\s*```') {
                $jsonStr = $Matches['json']
            } else {
                $jsonStr = $Content.Trim()
            }
        }

        # 3. Parse JSON
        try {
            # Final validation check via native if available (optional but good for strict mode)
            if ($Strict -and [PcaiNative.PcaiCore]::IsAvailable) {
                if (-not [PcaiNative.PcaiCore]::IsValidJson($jsonStr)) {
                    throw 'Native validation failed: String is not valid JSON'
                }
            }

            return $jsonStr | ConvertFrom-Json
        } catch {
            if ($Strict) { throw "Failed to parse JSON: $_" }
            Write-Warning 'JSON parsing failed. Returning raw content.'
            return $Content
        }
    }
}
