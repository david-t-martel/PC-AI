$PC_AIRoot = 'c:\Users\david\PC_AI'

Write-Host 'Importing Common and Acceleration modules...'
Import-Module (Join-Path $PC_AIRoot 'Modules\PC-AI.Common') -Force
Import-Module (Join-Path $PC_AIRoot 'Modules\PC-AI.Acceleration') -Force

Write-Host 'Initializing PC-AI Native tools...'
Initialize-PcaiNative -Force -Verbose

$TestPath = Join-Path $PC_AIRoot 'Modules\PC-AI.Hardware\Tests\PC-AI.Hardware.Tests.ps1'
Write-Host "Running Pester tests: $TestPath"
Invoke-Pester -Path $TestPath
