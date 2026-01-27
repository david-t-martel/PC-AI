function Invoke-LLMChatTui {
    <#
    .SYNOPSIS
        Launches the PC_AI chat TUI for LLM interaction.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $candidates = @(
        'C:\Users\david\bin\PcaiChatTui.exe',
        'C:\Users\david\PC_AI\Native\PcaiChatTui\bin\Release\net8.0\win-x64\PcaiChatTui.exe',
        'C:\Users\david\PC_AI\Native\PcaiChatTui\bin\Release\net8.0\win-x64\publish\PcaiChatTui.exe'
    )

    $exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe) {
        throw "PcaiChatTui.exe not found. Build or publish PC_AI\Native\PcaiChatTui first."
    }

    & $exe @Arguments
}
