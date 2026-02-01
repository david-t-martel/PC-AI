# Check all llama-cpp-sys build directories
$dirs = Get-ChildItem "T:\RustCache\cargo-target\release\build" -Filter "llama-cpp-sys-2-*" -Directory -ErrorAction SilentlyContinue
foreach ($d in $dirs) {
    Write-Host $d.FullName
    $out = Join-Path $d.FullName "out"
    if (Test-Path $out) {
        Write-Host "  has out dir"
        $buildDir = Join-Path $out "build"
        if (Test-Path $buildDir) {
            $ninja = Join-Path $buildDir "build.ninja"
            if (Test-Path $ninja) {
                Write-Host "    build.ninja EXISTS"
            } else {
                Write-Host "    build.ninja MISSING"
            }
            $cache = Join-Path $buildDir "CMakeCache.txt"
            if (Test-Path $cache) {
                Write-Host "    CMakeCache.txt EXISTS"
            }
        } else {
            Write-Host "    build subdir MISSING"
        }
    } else {
        Write-Host "  no out dir"
    }
}
