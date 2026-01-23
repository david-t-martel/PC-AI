<#
.SYNOPSIS
    Unit tests for PC-AI.Cleanup module

.DESCRIPTION
    Tests PATH cleanup, duplicate file detection, and temporary file removal
#>

BeforeAll {
    # Import module under test
    $ModulePath = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.Cleanup\PC-AI.Cleanup.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop

    # Import mock data
    $MockDataPath = Join-Path $PSScriptRoot '..\Fixtures\MockData.psm1'
    Import-Module $MockDataPath -Force -ErrorAction Stop
}

Describe "Get-PathDuplicates" -Tag 'Unit', 'Cleanup', 'Fast' {
    Context "When PATH has duplicate entries" {
        BeforeAll {
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    Path = "C:\Windows\System32;C:\Program Files\Git\cmd;C:\Windows\System32;C:\Users\david\bin;C:\Program Files\Git\cmd"
                }
            } -ModuleName PC-AI.Cleanup
        }

        It "Should detect duplicate entries" {
            $result = Get-PathDuplicates
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should list all duplicates" {
            $result = Get-PathDuplicates
            $result | Should -Match "C:\\Windows\\System32"
            $result | Should -Match "C:\\Program Files\\Git\\cmd"
        }

        It "Should count duplicate occurrences" {
            $result = Get-PathDuplicates
            $result | Should -Match "\(2\)|appears 2|twice"
        }
    }

    Context "When PATH has no duplicates" {
        BeforeAll {
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    Path = "C:\Windows\System32;C:\Program Files\Git\cmd;C:\Users\david\bin"
                }
            } -ModuleName PC-AI.Cleanup
        }

        It "Should return empty or 'none' message" {
            $result = Get-PathDuplicates
            $result | Should -Match "No duplicates|None found|^$"
        }
    }

    Context "When checking User PATH" {
        BeforeAll {
            Mock Get-ItemProperty {
                param($Path, $Name)
                if ($Path -match "Environment$") {
                    [PSCustomObject]@{
                        Path = "C:\Users\david\bin;C:\Users\david\.local\bin;C:\Users\david\bin"
                    }
                }
            } -ModuleName PC-AI.Cleanup
        }

        It "Should support User scope" {
            $result = Get-PathDuplicates -Scope User
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "When PATH variable is empty" {
        BeforeAll {
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    Path = ""
                }
            } -ModuleName PC-AI.Cleanup
        }

        It "Should handle empty PATH gracefully" {
            $result = Get-PathDuplicates
            $result | Should -Match "Empty|No entries"
        }
    }
}

Describe "Repair-MachinePath" -Tag 'Unit', 'Cleanup', 'Slow', 'RequiresAdmin' {
    Context "When removing duplicate PATH entries" {
        BeforeAll {
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    Path = "C:\Windows\System32;C:\Program Files\Git\cmd;C:\Windows\System32;C:\Users\david\bin"
                }
            } -ModuleName PC-AI.Cleanup

            Mock Set-ItemProperty {} -ModuleName PC-AI.Cleanup
            Mock Test-Path { $true } -ModuleName PC-AI.Cleanup
        }

        It "Should remove duplicate entries" {
            Repair-MachinePath

            Should -Invoke Set-ItemProperty -ModuleName PC-AI.Cleanup -ParameterFilter {
                $Value -notmatch "C:\\Windows\\System32.*C:\\Windows\\System32"
            }
        }

        It "Should preserve unique entries" {
            Repair-MachinePath

            Should -Invoke Set-ItemProperty -ModuleName PC-AI.Cleanup -ParameterFilter {
                $Value -match "C:\\Program Files\\Git\\cmd" -and
                $Value -match "C:\\Users\\david\\bin"
            }
        }

        It "Should require Administrator privileges" {
            Should -Invoke Set-ItemProperty -ModuleName PC-AI.Cleanup -ParameterFilter {
                $Path -match "SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment"
            }
        }
    }

    Context "When removing invalid PATH entries" {
        BeforeAll {
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    Path = "C:\Windows\System32;C:\NonExistent\Path;C:\Program Files\Git\cmd"
                }
            } -ModuleName PC-AI.Cleanup

            Mock Set-ItemProperty {} -ModuleName PC-AI.Cleanup
            Mock Test-Path {
                param($Path)
                $Path -ne "C:\NonExistent\Path"
            } -ModuleName PC-AI.Cleanup
        }

        It "Should remove invalid paths when RemoveInvalid is specified" {
            Repair-MachinePath -RemoveInvalid

            Should -Invoke Set-ItemProperty -ModuleName PC-AI.Cleanup -ParameterFilter {
                $Value -notmatch "NonExistent"
            }
        }

        It "Should keep valid paths" {
            Repair-MachinePath -RemoveInvalid

            Should -Invoke Set-ItemProperty -ModuleName PC-AI.Cleanup -ParameterFilter {
                $Value -match "C:\\Windows\\System32" -and
                $Value -match "C:\\Program Files\\Git\\cmd"
            }
        }
    }

    Context "When not running as Administrator" {
        BeforeAll {
            Mock Set-ItemProperty { throw "Access denied" } -ModuleName PC-AI.Cleanup
        }

        It "Should require Administrator privileges" {
            { Repair-MachinePath -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When WhatIf is specified" {
        BeforeAll {
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    Path = "C:\Windows\System32;C:\Windows\System32"
                }
            } -ModuleName PC-AI.Cleanup

            Mock Set-ItemProperty {} -ModuleName PC-AI.Cleanup
        }

        It "Should not modify PATH with WhatIf" {
            Repair-MachinePath -WhatIf

            Should -Invoke Set-ItemProperty -ModuleName PC-AI.Cleanup -Times 0
        }
    }
}

Describe "Find-DuplicateFiles" -Tag 'Unit', 'Cleanup', 'Slow' {
    Context "When scanning for duplicate files" {
        BeforeAll {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        FullName = "C:\Temp\file1.txt"
                        Length = 1024
                    }
                    [PSCustomObject]@{
                        FullName = "C:\Temp\file2.txt"
                        Length = 1024
                    }
                    [PSCustomObject]@{
                        FullName = "C:\Temp\file3.txt"
                        Length = 2048
                    }
                )
            } -ModuleName PC-AI.Cleanup

            Mock Get-FileHash {
                param($Path)
                if ($Path -match "file[12]\.txt") {
                    [PSCustomObject]@{
                        Hash = "ABC123"
                        Path = $Path
                    }
                } else {
                    [PSCustomObject]@{
                        Hash = "DEF456"
                        Path = $Path
                    }
                }
            } -ModuleName PC-AI.Cleanup
        }

        It "Should detect duplicate files by hash" {
            $result = Find-DuplicateFiles -Path "C:\Temp"
            $result | Where-Object { $_.Hash -eq "ABC123" } | Should -Not -BeNullOrEmpty
        }

        It "Should group files by size first" {
            Find-DuplicateFiles -Path "C:\Temp"

            Should -Invoke Get-FileHash -ModuleName PC-AI.Cleanup -Times 2  # Only same-size files
        }

        It "Should return file paths" {
            $result = Find-DuplicateFiles -Path "C:\Temp"
            $result[0] | Should -HaveProperty FullName
        }
    }

    Context "When no duplicates exist" {
        BeforeAll {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{ FullName = "C:\Temp\file1.txt"; Length = 1024 }
                    [PSCustomObject]@{ FullName = "C:\Temp\file2.txt"; Length = 2048 }
                )
            } -ModuleName PC-AI.Cleanup

            Mock Get-FileHash {
                param($Path)
                [PSCustomObject]@{
                    Hash = [guid]::NewGuid().ToString()
                    Path = $Path
                }
            } -ModuleName PC-AI.Cleanup
        }

        It "Should return empty result" {
            $result = Find-DuplicateFiles -Path "C:\Temp"
            $result | Should -BeNullOrEmpty
        }
    }

    Context "When path does not exist" {
        BeforeAll {
            Mock Get-ChildItem { throw "Path not found" } -ModuleName PC-AI.Cleanup
        }

        It "Should handle invalid path" {
            { Find-DuplicateFiles -Path "C:\NonExistent" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When filtering by extension" {
        BeforeAll {
            Mock Get-ChildItem {
                param($Path, $Filter, $Recurse)
                if ($Filter -eq "*.txt") {
                    @(
                        [PSCustomObject]@{ FullName = "C:\Temp\file1.txt"; Length = 1024 }
                    )
                }
            } -ModuleName PC-AI.Cleanup
        }

        It "Should filter by extension" {
            Find-DuplicateFiles -Path "C:\Temp" -Extension "*.txt"

            Should -Invoke Get-ChildItem -ModuleName PC-AI.Cleanup -ParameterFilter {
                $Filter -eq "*.txt"
            }
        }
    }
}

Describe "Clear-TempFiles" -Tag 'Unit', 'Cleanup', 'Slow' {
    Context "When clearing Windows temp files" {
        BeforeAll {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        FullName = "C:\Windows\Temp\file1.tmp"
                        LastWriteTime = (Get-Date).AddDays(-10)
                    }
                    [PSCustomObject]@{
                        FullName = "C:\Windows\Temp\file2.log"
                        LastWriteTime = (Get-Date).AddDays(-5)
                    }
                )
            } -ModuleName PC-AI.Cleanup

            Mock Remove-Item {} -ModuleName PC-AI.Cleanup
        }

        It "Should remove old temp files" {
            Clear-TempFiles -OlderThanDays 7

            Should -Invoke Remove-Item -ModuleName PC-AI.Cleanup -Times 1
        }

        It "Should skip recent files" {
            Clear-TempFiles -OlderThanDays 7

            Should -Invoke Remove-Item -ModuleName PC-AI.Cleanup -Times 0 -ParameterFilter {
                $Path -match "file2\.log"
            }
        }

        It "Should clean multiple temp locations" {
            Clear-TempFiles

            Should -Invoke Get-ChildItem -ModuleName PC-AI.Cleanup -ParameterFilter {
                $Path -match "Windows\\Temp|Users\\.*\\AppData\\Local\\Temp"
            }
        }
    }

    Context "When WhatIf is specified" {
        BeforeAll {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        FullName = "C:\Temp\file1.tmp"
                        LastWriteTime = (Get-Date).AddDays(-10)
                    }
                )
            } -ModuleName PC-AI.Cleanup

            Mock Remove-Item {} -ModuleName PC-AI.Cleanup
        }

        It "Should not delete files with WhatIf" {
            Clear-TempFiles -OlderThanDays 7 -WhatIf

            Should -Invoke Remove-Item -ModuleName PC-AI.Cleanup -Times 0
        }
    }

    Context "When files are in use" {
        BeforeAll {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        FullName = "C:\Temp\locked.tmp"
                        LastWriteTime = (Get-Date).AddDays(-10)
                    }
                )
            } -ModuleName PC-AI.Cleanup

            Mock Remove-Item { throw "File is in use" } -ModuleName PC-AI.Cleanup
        }

        It "Should handle locked files gracefully" {
            { Clear-TempFiles -OlderThanDays 7 -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
}

AfterAll {
    Remove-Module PC-AI.Cleanup -Force -ErrorAction SilentlyContinue
    Remove-Module MockData -Force -ErrorAction SilentlyContinue
}
