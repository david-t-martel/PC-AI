# Check PcaiNative.dll types
Copy-Item 'C:\Users\david\PC_AI\Native\PcaiNative\bin\Release\net8.0\win-x64\PcaiNative.dll' 'C:\Users\david\PC_AI\bin\' -Force

$assembly = [System.Reflection.Assembly]::LoadFrom('C:\Users\david\PC_AI\bin\PcaiNative.dll')
Write-Host "Public types in PcaiNative.dll:"
$assembly.GetTypes() | Where-Object { $_.IsPublic } | ForEach-Object { Write-Host "  - $($_.FullName)" }
