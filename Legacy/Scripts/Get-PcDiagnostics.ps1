#Wrapper script to maintain backward compatibility
# Imports the new modular architecture to generate the same report

$ScriptDir = $PSScriptRoot
$ModulesDir = Join-Path $ScriptDir 'Modules'

# Import Modules
Import-Module (Join-Path $ModulesDir 'PC-AI.Hardware') -Force
# Try import performance module if available (build artifact)
try { Import-Module (Join-Path $ModulesDir 'PC-AI.Performance') -ErrorAction Stop } catch { Write-Verbose 'Native performance module not loaded.' }

$reportPath = Join-Path $env:USERPROFILE 'Desktop\Hardware-Diagnostics-Report.txt'
"=== Hardware & Device Diagnostics Report ($(Get-Date)) ===`r`n" | Out-File $reportPath -Encoding UTF8

'== 1. Devices with Errors in Device Manager ==' | Add-Content $reportPath
try {
	$errs = Get-PcDeviceError
	if ($errs) { $errs | Format-Table -AutoSize | Out-String | Add-Content $reportPath }
	else { 'No devices reporting errors.' | Add-Content $reportPath }
} catch { "Error Querying: $_" | Add-Content $reportPath }

"`r`n== 2. Disk SMART Overall Status ==" | Add-Content $reportPath
try {
	Get-PcDiskStatus | Out-String | Add-Content $reportPath
} catch { "Error Querying: $_" | Add-Content $reportPath }

"`r`n== 3. USB Controllers and Devices ==" | Add-Content $reportPath
try {
	Get-PcUsbStatus | Format-Table -AutoSize | Out-String | Add-Content $reportPath
} catch { "Error Querying: $_" | Add-Content $reportPath }

"`r`n== 4. Network Adapter Status ==" | Add-Content $reportPath
try {
	Get-PcNetworkStatus | Format-Table -AutoSize | Out-String | Add-Content $reportPath
} catch { "Error Querying: $_" | Add-Content $reportPath }

"`r`n== 5. Recent Critical System Events (Hardware) ==" | Add-Content $reportPath
try {
	$evts = Get-PcSystemEvent
	if ($evts) { $evts | Format-List | Out-String | Add-Content $reportPath }
	else { 'No critical hardware events in last 3 days.' | Add-Content $reportPath }
} catch { "Error Querying: $_" | Add-Content $reportPath }

if (Get-Command Get-PcaiTopProcess -ErrorAction SilentlyContinue) {
	"`r`n== 6. Perf: Top CPU Processes ==" | Add-Content $reportPath
	Get-PcaiTopProcess -SortBy cpu -Top 5 | Format-Table -AutoSize | Out-String | Add-Content $reportPath
}

Write-Host "Report generated at: $reportPath" -ForegroundColor Green
