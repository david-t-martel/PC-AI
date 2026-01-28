# Requires -Version 5.1
$url = "http://127.0.0.1:8000/v1/chat/completions"
$payload = @{
    model = "functiongemma-270m-it"
    messages = @(@{ role = "user"; content = "Hello, are you active?" })
    temperature = 0.0
    max_tokens = 10
} | ConvertTo-Json

Write-Host "Sending test inference to vLLM at $url..." -ForegroundColor Cyan
try {
    $resp = Invoke-RestMethod -Uri $url -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 30
    Write-Host "SUCCESS: vLLM responded correctly." -ForegroundColor Green
    $resp.choices[0].message.content | Write-Host -ForegroundColor Gray
} catch {
    Write-Error "FAILED: vLLM inference failed. Detail: $_"
}
