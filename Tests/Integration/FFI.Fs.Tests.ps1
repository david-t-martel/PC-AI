#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    FFI integration tests for PCAI Filesystem native library.

.DESCRIPTION
    Tests the Rust pcai_fs DLL loading and C# FsModule wrapper functionality including:
    1. File deletion operations
    2. Directory deletion with recursive option
    3. Text replacement in files
    4. Backup creation during replacements
    5. Error handling for invalid paths

.NOTES
    Run these tests after building the native modules with:
    .\Native\build.ps1 -Test

    Tests will gracefully skip if the native DLL is not available.
#>

BeforeAll {
    # Project paths
    $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BinDir = Join-Path $ProjectRoot "bin"
    $script:NativeDir = Join-Path $ProjectRoot "Native"
    $script:CSharpDir = Join-Path $NativeDir "PcaiNative"

    # Helper function to check if DLL exists
    function Test-DllExists {
        param([string]$DllName)
        $path = Join-Path $BinDir $DllName
        return Test-Path $path
    }

    # Helper function to get DLL path
    function Get-DllPath {
        param([string]$DllName)
        return Join-Path $BinDir $DllName
    }
}

Describe "PCAI Filesystem Module - Phase 2" -Tag "FFI", "Fs", "Phase2" {

    Context "Build Artifacts" {

        It "pcai_fs crate exists" {
            Test-Path (Join-Path $NativeDir "pcai_core\pcai_fs") | Should -Be $true
        }

        It "FsModule.cs exists" {
            Test-Path (Join-Path $CSharpDir "FsModule.cs") | Should -Be $true
        }

        It "Models.cs exists with PcaiStatus enum" {
            Test-Path (Join-Path $CSharpDir "Models.cs") | Should -Be $true
        }
    }

    Context "DLL Loading" {

        BeforeAll {
            # Build if DLL doesn't exist
            if (-not (Test-DllExists "pcai_fs.dll")) {
                Write-Host "Building native modules..." -ForegroundColor Yellow
                Push-Location $NativeDir
                try {
                    & .\build.ps1 2>&1 | Out-Null
                }
                finally {
                    Pop-Location
                }
            }

            # Try to load PcaiNative assembly
            $script:PcaiNativeDll = Get-DllPath "PcaiNative.dll"
            $script:NativeAvailable = $false

            if (Test-Path $script:PcaiNativeDll) {
                $env:PATH = "$BinDir;$env:PATH"
                try {
                    Add-Type -Path $script:PcaiNativeDll -ErrorAction SilentlyContinue
                    $script:NativeAvailable = [PcaiNative.FsModule]::IsAvailable
                } catch {
                    Write-Warning "Failed to load PcaiNative: $_"
                }
            } else {
                Write-Warning "PcaiNative.dll not found at $script:PcaiNativeDll"
            }
        }

        It "pcai_fs.dll exists after build" {
            if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because "Rust toolchain not installed"
            }

            $dllPath = Get-DllPath "pcai_fs.dll"
            if (Test-Path $dllPath) {
                $true | Should -Be $true
            }
            else {
                Set-ItResult -Skipped -Because "pcai_fs.dll not built (run .\Native\build.ps1 first)"
            }
        }

        It "PcaiNative.dll exists after build" {
            if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because ".NET SDK not installed"
            }

            $dllPath = Get-DllPath "PcaiNative.dll"
            if (Test-Path $dllPath) {
                $true | Should -Be $true
            }
            else {
                Set-ItResult -Skipped -Because "PcaiNative.dll not built (run .\Native\build.ps1 first)"
            }
        }

        It "FsModule reports availability status" {
            if (-not (Test-Path $script:PcaiNativeDll)) {
                Set-ItResult -Skipped -Because "PcaiNative.dll not available"
            }
            else {
                try {
                    $status = $script:NativeAvailable
                    $status | Should -BeOfType [bool]
                }
                catch {
                    Set-ItResult -Skipped -Because "Failed to query FsModule availability"
                }
            }
        }
    }

    Context "DeleteItem Operations" -Skip:(-not $script:NativeAvailable) {

        BeforeEach {
            $script:TestDir = Join-Path $env:TEMP "pcai-ffi-fs-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:TestDir) {
                Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should delete a file successfully" {
            $testFile = Join-Path $script:TestDir 'test.txt'
            Set-Content -Path $testFile -Value 'test content'
            Test-Path $testFile | Should -BeTrue

            $status = [PcaiNative.FsModule]::DeleteItem($testFile, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)
            Test-Path $testFile | Should -BeFalse
        }

        It "Should delete an empty directory" {
            $emptyDir = Join-Path $script:TestDir 'empty'
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
            Test-Path $emptyDir | Should -BeTrue

            $status = [PcaiNative.FsModule]::DeleteItem($emptyDir, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)
            Test-Path $emptyDir | Should -BeFalse
        }

        It "Should delete a directory recursively with contents" {
            $subDir = Join-Path $script:TestDir 'subdir'
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null
            Set-Content -Path (Join-Path $subDir 'nested.txt') -Value 'nested content'
            Set-Content -Path (Join-Path $script:TestDir 'root.txt') -Value 'root content'

            $status = [PcaiNative.FsModule]::DeleteItem($script:TestDir, $true)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)
            Test-Path $script:TestDir | Should -BeFalse
        }

        It "Should return PathNotFound for nonexistent path" {
            $nonExistentPath = "C:\NonExistent\Path\$(Get-Random)\file.txt"
            $status = [PcaiNative.FsModule]::DeleteItem($nonExistentPath, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::PathNotFound)
        }

        It "Should handle file with special characters in name" {
            $specialFile = Join-Path $script:TestDir 'test file (copy) [1].txt'
            Set-Content -Path $specialFile -Value 'content'
            Test-Path $specialFile | Should -BeTrue

            $status = [PcaiNative.FsModule]::DeleteItem($specialFile, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)
            Test-Path $specialFile | Should -BeFalse
        }
    }

    Context "ReplaceInFile Operations" -Skip:(-not $script:NativeAvailable) {

        BeforeEach {
            $script:TestDir = Join-Path $env:TEMP "pcai-ffi-fs-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:TestDir) {
                Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should replace literal text in a file" {
            $testFile = Join-Path $script:TestDir 'test.txt'
            Set-Content -Path $testFile -Value 'Hello World'

            $status = [PcaiNative.FsModule]::ReplaceInFile($testFile, 'World', 'Rust', $false, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)
            Get-Content $testFile | Should -Be 'Hello Rust'
        }

        It "Should handle multiple replacements in same file" {
            $testFile = Join-Path $script:TestDir 'multi.txt'
            Set-Content -Path $testFile -Value "foo bar foo baz foo"

            $status = [PcaiNative.FsModule]::ReplaceInFile($testFile, 'foo', 'qux', $false, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)
            Get-Content $testFile | Should -Be "qux bar qux baz qux"
        }

        It "Should create backup when requested" {
            $testFile = Join-Path $script:TestDir 'backup-test.txt'
            Set-Content -Path $testFile -Value 'Original Content'

            $status = [PcaiNative.FsModule]::ReplaceInFile($testFile, 'Original', 'Modified', $false, $true)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)

            # Verify file was modified
            Get-Content $testFile | Should -Be 'Modified Content'

            # Verify backup was created
            Test-Path "$testFile.bak" | Should -BeTrue
            Get-Content "$testFile.bak" | Should -Be 'Original Content'
        }

        It "Should handle multiline content correctly" {
            $testFile = Join-Path $script:TestDir 'multiline.txt'
            $originalContent = @"
Line 1 with target
Line 2 without
Line 3 with target
"@
            Set-Content -Path $testFile -Value $originalContent

            $status = [PcaiNative.FsModule]::ReplaceInFile($testFile, 'target', 'replacement', $false, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)

            $content = Get-Content $testFile -Raw
            $content | Should -Match 'replacement'
            $content | Should -Not -Match 'target'
        }

        It "Should return PathNotFound for nonexistent file" {
            $nonExistentFile = Join-Path $script:TestDir "nonexistent-$(Get-Random).txt"
            $status = [PcaiNative.FsModule]::ReplaceInFile($nonExistentFile, 'foo', 'bar', $false, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::PathNotFound)
        }

        It "Should handle empty replacement string" {
            $testFile = Join-Path $script:TestDir 'empty-replace.txt'
            Set-Content -Path $testFile -Value 'Remove this word: target'

            $status = [PcaiNative.FsModule]::ReplaceInFile($testFile, 'target', '', $false, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)
            Get-Content $testFile | Should -Be 'Remove this word: '
        }

        It "Should handle files with UTF-8 content" {
            $testFile = Join-Path $script:TestDir 'utf8.txt'
            $utf8Content = "Hello 世界 français émojis 🚀🔥"
            Set-Content -Path $testFile -Value $utf8Content -Encoding UTF8

            $status = [PcaiNative.FsModule]::ReplaceInFile($testFile, '世界', 'world', $false, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)

            $result = Get-Content $testFile -Encoding UTF8
            $result | Should -Match 'world'
            $result | Should -Match 'français'
            $result | Should -Match '🚀'
        }
    }

    Context "ReplaceInFile Regex Operations" -Skip:(-not $script:NativeAvailable) {

        BeforeEach {
            $script:TestDir = Join-Path $env:TEMP "pcai-ffi-fs-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $script:TestDir) {
                Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should support regex pattern matching" {
            $testFile = Join-Path $script:TestDir 'regex.txt'
            Set-Content -Path $testFile -Value 'Error: 123, Warning: 456, Error: 789'

            # Replace all numbers after "Error:" with "XXX"
            $status = [PcaiNative.FsModule]::ReplaceInFile($testFile, 'Error:\s*\d+', 'Error: XXX', $true, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)

            $content = Get-Content $testFile
            $content | Should -Match 'Error: XXX.*Warning: 456.*Error: XXX'
        }

        It "Should handle regex with capture groups" {
            $testFile = Join-Path $script:TestDir 'capture.txt'
            Set-Content -Path $testFile -Value 'version=1.2.3 build=456'

            # Swap version and build using capture groups
            $status = [PcaiNative.FsModule]::ReplaceInFile($testFile, '(\d+\.\d+\.\d+)', 'v$1', $true, $false)
            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)

            $content = Get-Content $testFile
            $content | Should -Match 'version=v1\.2\.3'
        }
    }

    Context "Performance Baseline" -Tag "Performance" {

        BeforeAll {
            if ($script:NativeAvailable) {
                $script:PerfTestDir = Join-Path $env:TEMP "pcai-ffi-perf-$(Get-Random)"
                New-Item -ItemType Directory -Path $script:PerfTestDir -Force | Out-Null
            }
        }

        AfterAll {
            if (Test-Path $script:PerfTestDir -ErrorAction SilentlyContinue) {
                Remove-Item -Path $script:PerfTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "DeleteItem completes in reasonable time (<100ms for 100 files)" -Skip:(-not $script:NativeAvailable) {
            # Create 100 test files
            for ($i = 0; $i -lt 100; $i++) {
                $file = Join-Path $script:PerfTestDir "file_$i.txt"
                Set-Content -Path $file -Value "Content $i"
            }

            $sw = [System.Diagnostics.Stopwatch]::StartNew()

            # Delete all files
            Get-ChildItem $script:PerfTestDir -File | ForEach-Object {
                $null = [PcaiNative.FsModule]::DeleteItem($_.FullName, $false)
            }

            $sw.Stop()
            $sw.ElapsedMilliseconds | Should -BeLessThan 100
        }

        It "ReplaceInFile completes in reasonable time (<50ms for 1KB file)" -Skip:(-not $script:NativeAvailable) {
            $testFile = Join-Path $script:PerfTestDir 'perf.txt'

            # Create a 1KB file
            $content = "test " * 200  # ~1KB
            Set-Content -Path $testFile -Value $content

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $status = [PcaiNative.FsModule]::ReplaceInFile($testFile, 'test', 'replaced', $false, $false)
            $sw.Stop()

            $status | Should -Be ([PcaiNative.PcaiStatus]::Success)
            $sw.ElapsedMilliseconds | Should -BeLessThan 50
        }
    }

    Context "Error Handling" -Skip:(-not $script:NativeAvailable) {

        It "Should handle read-only file gracefully" {
            $testDir = Join-Path $env:TEMP "pcai-readonly-$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            try {
                $readOnlyFile = Join-Path $testDir 'readonly.txt'
                Set-Content -Path $readOnlyFile -Value 'content'
                Set-ItemProperty -Path $readOnlyFile -Name IsReadOnly -Value $true

                $status = [PcaiNative.FsModule]::ReplaceInFile($readOnlyFile, 'content', 'new', $false, $false)

                # Should return PermissionDenied or IoError
                $status | Should -BeIn @([PcaiNative.PcaiStatus]::PermissionDenied, [PcaiNative.PcaiStatus]::IoError)
            }
            finally {
                if (Test-Path $testDir) {
                    # Remove read-only attribute before cleanup
                    Get-ChildItem $testDir -Recurse -Force | ForEach-Object {
                        $_.IsReadOnly = $false
                    }
                    Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "Should handle directory when file expected" {
            $testDir = Join-Path $env:TEMP "pcai-dir-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            try {
                # Try to replace in a directory (not a file)
                $status = [PcaiNative.FsModule]::ReplaceInFile($testDir, 'foo', 'bar', $false, $false)

                # Should not be Success
                $status | Should -Not -Be ([PcaiNative.PcaiStatus]::Success)
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
