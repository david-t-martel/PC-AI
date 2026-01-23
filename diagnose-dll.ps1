# Diagnose DLL loading issues
$ErrorActionPreference = 'Continue'

$binDir = 'C:\Users\david\PC_AI\bin'
$wrapperDll = Join-Path $binDir 'PcaiNative.dll'
$coreDll = Join-Path $binDir 'pcai_core_lib.dll'
$searchDll = Join-Path $binDir 'pcai_search.dll'

Write-Host "=== DLL Diagnostic ===" -ForegroundColor Cyan

# Check if files exist
Write-Host "`n1. File Existence Check:" -ForegroundColor Yellow
Write-Host "   PcaiNative.dll: $(Test-Path $wrapperDll)"
Write-Host "   pcai_core_lib.dll: $(Test-Path $coreDll)"
Write-Host "   pcai_search.dll: $(Test-Path $searchDll)"

# Check file sizes
Write-Host "`n2. File Sizes:" -ForegroundColor Yellow
Get-ChildItem $binDir -Filter '*.dll' | ForEach-Object {
    Write-Host ("   {0}: {1:N0} bytes" -f $_.Name, $_.Length)
}

# Check if already loaded
Write-Host "`n3. Already Loaded Assemblies:" -ForegroundColor Yellow
$loaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.GetName().Name -like 'Pcai*' }
if ($loaded) {
    $loaded | ForEach-Object { Write-Host "   $($_.GetName().Name) v$($_.GetName().Version)" }
} else {
    Write-Host "   (none)"
}

# Try to load
Write-Host "`n4. Attempting to Load PcaiNative.dll:" -ForegroundColor Yellow
try {
    Add-Type -Path $wrapperDll -ErrorAction Stop
    Write-Host "   SUCCESS: Assembly loaded" -ForegroundColor Green

    # Check types
    Write-Host "`n5. Checking Types:" -ForegroundColor Yellow
    $types = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'PcaiNative' } |
        ForEach-Object { $_.GetExportedTypes() }
    $types | ForEach-Object { Write-Host "   $_" }

    # Try to access static properties
    Write-Host "`n6. Testing Native Availability:" -ForegroundColor Yellow
    try {
        $coreAvail = [PcaiNative.PcaiCore]::IsAvailable
        Write-Host "   PcaiCore.IsAvailable: $coreAvail" -ForegroundColor $(if($coreAvail){'Green'}else{'Red'})
    } catch {
        Write-Host "   PcaiCore.IsAvailable ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }

    try {
        $searchAvail = [PcaiNative.PcaiSearch]::IsAvailable
        Write-Host "   PcaiSearch.IsAvailable: $searchAvail" -ForegroundColor $(if($searchAvail){'Green'}else{'Red'})
    } catch {
        Write-Host "   PcaiSearch.IsAvailable ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}
catch [System.Reflection.ReflectionTypeLoadException] {
    Write-Host "   FAILED: ReflectionTypeLoadException" -ForegroundColor Red
    Write-Host "`n   LoaderExceptions:" -ForegroundColor Red
    $_.Exception.LoaderExceptions | ForEach-Object {
        Write-Host "   - $($_.Message)" -ForegroundColor Red
    }
}
catch {
    Write-Host "   FAILED: $($_.Exception.GetType().Name)" -ForegroundColor Red
    Write-Host "   Message: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.Exception.InnerException) {
        Write-Host "   Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
}

# Check native DLL exports
Write-Host "`n7. Native DLL P/Invoke Test:" -ForegroundColor Yellow
try {
    # Define a simple P/Invoke to test if native DLLs are loadable
    $code = @"
using System;
using System.Runtime.InteropServices;

public class NativeDllTest {
    [DllImport("pcai_core_lib.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern uint pcai_core_test();

    [DllImport("pcai_search.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern uint pcai_search_test();
}
"@

    Add-Type -TypeDefinition $code -ErrorAction Stop

    # Test core DLL
    try {
        $testResult = [NativeDllTest]::pcai_core_test()
        $expected = 0x50435F4131  # PC_A1 in hex
        Write-Host "   pcai_core_test(): 0x$($testResult.ToString('X')) (expected: 0x$($expected.ToString('X')))" -ForegroundColor $(if($testResult -eq $expected){'Green'}else{'Yellow'})
    } catch {
        Write-Host "   pcai_core_test() FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Test search DLL
    try {
        $testResult = [NativeDllTest]::pcai_search_test()
        Write-Host "   pcai_search_test(): 0x$($testResult.ToString('X'))" -ForegroundColor Green
    } catch {
        Write-Host "   pcai_search_test() FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
}
catch {
    Write-Host "   P/Invoke setup FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Diagnostic Complete ===" -ForegroundColor Cyan
