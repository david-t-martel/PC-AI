# Clean ALL llama-cpp-sys build caches (debug and release)
$targetDir = "T:\RustCache\cargo-target"
$patterns = @("debug\build", "release\build")

foreach ($pattern in $patterns) {
    $buildDir = Join-Path $targetDir $pattern
    if (Test-Path $buildDir) {
        $dirs = Get-ChildItem $buildDir -Filter "llama-cpp-sys-2-*" -Directory -ErrorAction SilentlyContinue
        foreach ($d in $dirs) {
            $outDir = Join-Path $d.FullName "out"
            if (Test-Path $outDir) {
                Write-Host "Removing: $outDir"
                Remove-Item $outDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
Write-Host "Cache clean complete"
