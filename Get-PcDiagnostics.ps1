
# ===== Hardware & Device Diagnostics - Read-Only Report =====
# This will create a text report on your Desktop summarizing low-level device issues.

$reportPath = Join-Path $env:USERPROFILE "Desktop\Hardware-Diagnostics-Report.txt"

"=== Hardware & Device Diagnostics Report ($(Get-Date)) ===`r`n" | Out-File $reportPath -Encoding UTF8

# 1. Devices with Errors in Device Manager
"== 1. Devices with Errors in Device Manager ==" | Add-Content $reportPath
try
{
	$devicesWithErrors = Get-CimInstance Win32_PnPEntity |
		Where-Object { $_.ConfigManagerErrorCode -ne 0 }

	if ($devicesWithErrors)
	{
		$devicesWithErrors |
			Select-Object Name, PNPClass, Manufacturer, ConfigManagerErrorCode, Status |
			Format-Table -AutoSize | Out-String | Add-Content $reportPath
	} else
	{
		"No devices reporting ConfigManagerErrorCode <> 0 (no obvious Device Manager errors)." |
			Add-Content $reportPath
	}
} catch
{
	"Failed to query PnP devices: $($_.Exception.Message)" | Add-Content $reportPath
}

"`r`n" | Add-Content $reportPath

# 2. Disk SMART overall status
"== 2. Disk SMART Overall Status ==" | Add-Content $reportPath
try
{
	$diskStatus = wmic diskdrive get model, status 2>&1
	$diskStatus | Out-String | Add-Content $reportPath
} catch
{
	"Failed to query disk SMART via wmic: $($_.Exception.Message)" | Add-Content $reportPath
}

"`r`n" | Add-Content $reportPath

# 3. Recent System Errors/Warnings related to disk/USB (last 3 days)
"== 3. Recent System Errors/Warnings (disk / storage / USB) - last 3 days ==" | Add-Content $reportPath
try
{
	$startTime = (Get-Date).AddDays(-3)
	$events = Get-WinEvent -FilterHashtable @{
		LogName = 'System'
		Level   = 1,2,3   # Critical, Error, Warning
		StartTime = $startTime
	} -ErrorAction SilentlyContinue | Where-Object {
		$_.ProviderName -match 'disk|storahci|nvme|usbhub|USB|nvstor|iaStor|stornvme|partmgr'
	}

	if ($events)
	{
		$events |
			Select-Object -First 50 TimeCreated, ProviderName, Id, LevelDisplayName, Message |
			Format-List | Out-String | Add-Content $reportPath
	} else
	{
		"No disk/USB-related critical/error/warning events found in the last 3 days." |
			Add-Content $reportPath
	}
} catch
{
	"Failed to query System events: $($_.Exception.Message)" | Add-Content $reportPath
}

"`r`n" | Add-Content $reportPath

# 4. USB controllers and USB-related devices status
"== 4. USB Controllers and USB Devices Status ==" | Add-Content $reportPath
try
{
	$usbDevices = Get-CimInstance Win32_PnPEntity |
		Where-Object { $_.PNPClass -eq 'USB' -or $_.Name -like '*USB*' }

	if ($usbDevices)
	{
		$usbDevices |
			Select-Object Name, PNPClass, Status, ConfigManagerErrorCode |
			Sort-Object ConfigManagerErrorCode, Name |
			Format-Table -AutoSize | Out-String | Add-Content $reportPath
	} else
	{
		"No USB devices found via Win32_PnPEntity." | Add-Content $reportPath
	}
} catch
{
	"Failed to query USB devices: $($_.Exception.Message)" | Add-Content $reportPath
}

"`r`n" | Add-Content $reportPath

# 5. Physical Network Adapters status
"== 5. Physical Network Adapters Status ==" | Add-Content $reportPath
try
{
	$net = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true }

	if ($net)
	{
		$net |
			Select-Object Name, NetEnabled, Status, MACAddress, Speed |
			Sort-Object Name |
			Format-Table -AutoSize | Out-String | Add-Content $reportPath
	} else
	{
		"No physical network adapters found via Win32_NetworkAdapter." | Add-Content $reportPath
	}
} catch
{
	"Failed to query network adapters: $($_.Exception.Message)" | Add-Content $reportPath
}

"`r`n" | Add-Content $reportPath

# 6. Summary hint section (high-level interpretation guidance)
"== 6. How to Read This Report (Quick Hints) ==" | Add-Content $reportPath
@"
- Section 1: Any devices listed here with ConfigManagerErrorCode <> 0 are candidates for driver/hardware issues.
- Section 2: Disk status should ideally show 'OK' for all drives.
- Section 3: Repeated errors from 'disk', 'nvme', 'storahci', or lots of USB warnings can indicate unstable hardware or cabling.
- Section 4: USB devices with non-zero ConfigManagerErrorCode or Status not equal to 'OK' are suspect.
- Section 5: Network adapters that are not NetEnabled but should be in use, or show unusual Status, may be misconfigured or failing.
"@ | Add-Content $reportPath

"`r`n=== End of Report ===" | Add-Content $reportPath

Write-Host ""
Write-Host "Hardware diagnostics report created:" -ForegroundColor Cyan
Write-Host "  $reportPath" -ForegroundColor Yellow
Write-Host ""
Write-Host "You can share the relevant sections or the whole file for interpretation." -ForegroundColor Cyan
``
