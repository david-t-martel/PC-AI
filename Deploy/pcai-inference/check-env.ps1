# Check environment after MSVC setup
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1' -SkipAutomaticLocation -HostArch amd64 -Arch amd64 | Out-Null

Write-Host "CL env: $env:CL"
Write-Host "_CL_ env: $env:_CL_"
Write-Host ""
Write-Host "Checking for problematic env vars..."

# Check for any env vars with paths containing spaces that might interfere
Get-ChildItem env: | Where-Object {
    $_.Value -like '*Program*' -and $_.Value -like '*MP*'
} | Select-Object Name, Value

# Simple compile test
$testFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.c'
"int main() { return 0; }" | Out-File -FilePath $testFile -Encoding ASCII

Write-Host ""
Write-Host "Testing cl.exe directly..."
& cl.exe /c $testFile /Fo"$env:TEMP\test.obj" 2>&1

Remove-Item $testFile -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\test.obj" -ErrorAction SilentlyContinue
