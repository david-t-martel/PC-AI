param(
    [int]$Iterations = 3,
    [int]$IntervalSeconds = 300,
    [int]$MaxScenarios = 6,
    [string]$BaseUrl = "http://127.0.0.1:8000",
    [string]$Model = "functiongemma-270m-it",
    [string]$ToolsPath = "C:\Users\david\PC_AI\Config\pcai-tools.json",
    [string]$SystemPrompt = "C:\Users\david\PC_AI\DIAGNOSE.md",
    [string]$ScenariosPath = "C:\Users\david\PC_AI\Deploy\functiongemma-finetune\scenarios.json"
)

function Invoke-EvalPrompt {
    param(
        [string]$Prompt,
        [string]$ExpectedTool
    )

    $cmd = @(
        "uv", "run", "python", "eval_harness.py",
        "--base-url", $BaseUrl,
        "--model", $Model,
        "--tools", $ToolsPath,
        "--prompt", $Prompt,
        "--system-prompt", $SystemPrompt
    )

    $raw = & $cmd 2>$null
    if (-not $raw) {
        return [PSCustomObject]@{ Prompt = $Prompt; ExpectedTool = $ExpectedTool; Status = 'NoOutput' }
    }

    $msg = $null
    try {
        $msg = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return [PSCustomObject]@{ Prompt = $Prompt; ExpectedTool = $ExpectedTool; Status = 'InvalidJson' }
    }

    $toolCalls = @()
    if ($msg.tool_calls) { $toolCalls = @($msg.tool_calls) }

    if ($ExpectedTool) {
        $toolName = $toolCalls | Select-Object -First 1 | ForEach-Object { $_.function.name }
        $ok = ($toolName -eq $ExpectedTool)
        return [PSCustomObject]@{
            Prompt = $Prompt
            ExpectedTool = $ExpectedTool
            ToolChosen = $toolName
            Status = if ($ok) { 'Ok' } else { 'Mismatch' }
        }
    }

    $content = $msg.content
    $noTool = (-not $toolCalls -or $toolCalls.Count -eq 0) -and ($content -match 'NO_TOOL')
    return [PSCustomObject]@{
        Prompt = $Prompt
        ExpectedTool = $null
        ToolChosen = if ($toolCalls.Count -gt 0) { ($toolCalls[0].function.name) } else { $null }
        Status = if ($noTool) { 'Ok' } else { 'Mismatch' }
    }
}

$scenarios = @()
if (Test-Path $ScenariosPath) {
    $data = Get-Content $ScenariosPath -Raw | ConvertFrom-Json
    $scenarios = $data.scenarios
}

if (-not $scenarios -or $scenarios.Count -eq 0) {
    Write-Error "No scenarios found at $ScenariosPath"
    exit 1
}

$sample = $scenarios | Select-Object -First $MaxScenarios

for ($i = 1; $i -le $Iterations; $i++) {
    Write-Host "[Monitor] Iteration $i/$Iterations" -ForegroundColor Cyan
    $results = @()
    foreach ($s in $sample) {
        $results += Invoke-EvalPrompt -Prompt $s.user_content -ExpectedTool $s.tool_name
    }

    $ok = ($results | Where-Object { $_.Status -eq 'Ok' }).Count
    $total = $results.Count
    Write-Host ("[Monitor] Pass {0}/{1}" -f $ok, $total) -ForegroundColor Green
    $results | Format-Table Prompt, ExpectedTool, ToolChosen, Status -AutoSize

    if ($i -lt $Iterations) {
        Start-Sleep -Seconds $IntervalSeconds
    }
}
