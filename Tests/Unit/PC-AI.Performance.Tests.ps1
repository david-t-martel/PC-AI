<#
.SYNOPSIS
    Unit tests for PC-AI.Performance module

.DESCRIPTION
    Tests disk space monitoring, process performance tracking, system resource watching, and disk optimization
#>

BeforeAll {
    # Import module under test
    $ModulePath = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.Performance\PC-AI.Performance.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop

    # Import mock data
    $MockDataPath = Join-Path $PSScriptRoot '..\Fixtures\MockData.psm1'
    Import-Module $MockDataPath -Force -ErrorAction Stop
}

Describe "Get-DiskSpace" -Tag 'Unit', 'Performance', 'Fast' {
    Context "When checking disk space with healthy drives" {
        BeforeAll {
            Mock Get-PSDrive {
                [PSCustomObject]@{
                    Name = 'C'
                    Used = 150GB
                    Free = 350GB
                    Provider = [PSCustomObject]@{ Name = 'FileSystem' }
                }
                [PSCustomObject]@{
                    Name = 'D'
                    Used = 500GB
                    Free = 1500GB
                    Provider = [PSCustomObject]@{ Name = 'FileSystem' }
                }
            } -ModuleName PC-AI.Performance
        }

        It "Should return disk space information" {
            $result = Get-DiskSpace
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should calculate total size correctly" {
            $result = Get-DiskSpace | Where-Object { $_.Drive -eq 'C:' }
            $result.TotalSizeGB | Should -BeGreaterThan 0
        }

        It "Should calculate percentage free" {
            $result = Get-DiskSpace | Where-Object { $_.Drive -eq 'C:' }
            $result.PercentFree | Should -BeGreaterThan 0
            $result.PercentFree | Should -BeLessOrEqual 100
        }

        It "Should filter file system drives only" {
            Should -Invoke Get-PSDrive -ModuleName PC-AI.Performance -ParameterFilter {
                $PSProvider -eq 'FileSystem'
            }
        }
    }

    Context "When disk space is low" {
        BeforeAll {
            Mock Get-PSDrive {
                [PSCustomObject]@{
                    Name = 'C'
                    Used = 460GB
                    Free = 40GB
                    Provider = [PSCustomObject]@{ Name = 'FileSystem' }
                }
            } -ModuleName PC-AI.Performance
        }

        It "Should detect low disk space" {
            $result = Get-DiskSpace
            $result.PercentFree | Should -BeLessThan 15
        }
    }

    Context "When disk space is critical" {
        BeforeAll {
            Mock Get-PSDrive {
                [PSCustomObject]@{
                    Name = 'C'
                    Used = 485GB
                    Free = 15GB
                    Provider = [PSCustomObject]@{ Name = 'FileSystem' }
                }
            } -ModuleName PC-AI.Performance
        }

        It "Should detect critical disk space" {
            $result = Get-DiskSpace
            $result.PercentFree | Should -BeLessThan 5
        }
    }

    Context "When filtering by drive letter" {
        BeforeAll {
            Mock Get-PSDrive {
                [PSCustomObject]@{
                    Name = 'C'
                    Used = 150GB
                    Free = 350GB
                    Provider = [PSCustomObject]@{ Name = 'FileSystem' }
                }
                [PSCustomObject]@{
                    Name = 'D'
                    Used = 500GB
                    Free = 1500GB
                    Provider = [PSCustomObject]@{ Name = 'FileSystem' }
                }
            } -ModuleName PC-AI.Performance
        }

        It "Should filter by specific drive" {
            $result = Get-DiskSpace -DriveLetter 'C'
            $result.Drive | Should -Be 'C:'
        }
    }
}

Describe "Get-ProcessPerformance" -Tag 'Unit', 'Performance', 'Fast' {
    Context "When monitoring process performance" {
        BeforeAll {
            Mock Get-Process {
                [PSCustomObject]@{
                    Name = "chrome"
                    Id = 1234
                    CPU = 45.5
                    WorkingSet = 500MB
                    Handles = 1500
                }
                [PSCustomObject]@{
                    Name = "Code"
                    Id = 5678
                    CPU = 12.3
                    WorkingSet = 300MB
                    Handles = 800
                }
            } -ModuleName PC-AI.Performance
        }

        It "Should return process information" {
            $result = Get-ProcessPerformance
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should include CPU usage" {
            $result = Get-ProcessPerformance
            $result[0].CPU | Should -BeGreaterThan 0
        }

        It "Should include memory usage" {
            $result = Get-ProcessPerformance
            $result[0].WorkingSet | Should -BeGreaterThan 0
        }

        It "Should sort by CPU usage by default" {
            $result = Get-ProcessPerformance
            $result[0].CPU | Should -BeGreaterOrEqual $result[1].CPU
        }
    }

    Context "When filtering by process name" {
        BeforeAll {
            Mock Get-Process {
                param($Name)
                if ($Name -eq "chrome") {
                    [PSCustomObject]@{
                        Name = "chrome"
                        Id = 1234
                        CPU = 45.5
                        WorkingSet = 500MB
                    }
                }
            } -ModuleName PC-AI.Performance
        }

        It "Should filter by process name" {
            $result = Get-ProcessPerformance -ProcessName "chrome"
            $result.Name | Should -Be "chrome"
        }
    }

    Context "When limiting top processes" {
        BeforeAll {
            Mock Get-Process {
                1..10 | ForEach-Object {
                    [PSCustomObject]@{
                        Name = "Process$_"
                        Id = $_
                        CPU = (100 - $_ * 5)
                        WorkingSet = (500MB - $_ * 10MB)
                    }
                }
            } -ModuleName PC-AI.Performance
        }

        It "Should limit results to top N processes" {
            $result = Get-ProcessPerformance -Top 5
            $result.Count | Should -Be 5
        }
    }

    Context "When no processes match" {
        BeforeAll {
            Mock Get-Process { throw "Process not found" } -ModuleName PC-AI.Performance
        }

        It "Should handle process not found" {
            { Get-ProcessPerformance -ProcessName "nonexistent" -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Watch-SystemResources" -Tag 'Unit', 'Performance', 'Slow' {
    Context "When monitoring system resources" {
        BeforeAll {
            Mock Get-Counter {
                [PSCustomObject]@{
                    CounterSamples = @(
                        [PSCustomObject]@{
                            Path = '\\localhost\processor(_total)\% processor time'
                            CookedValue = 35.5
                        }
                        [PSCustomObject]@{
                            Path = '\\localhost\memory\available mbytes'
                            CookedValue = 8192
                        }
                    )
                }
            } -ModuleName PC-AI.Performance

            Mock Start-Sleep {} -ModuleName PC-AI.Performance
        }

        It "Should collect CPU metrics" {
            Watch-SystemResources -Iterations 1

            Should -Invoke Get-Counter -ModuleName PC-AI.Performance -ParameterFilter {
                $Counter -contains "\Processor(_Total)\% Processor Time"
            }
        }

        It "Should collect memory metrics" {
            Watch-SystemResources -Iterations 1

            Should -Invoke Get-Counter -ModuleName PC-AI.Performance -ParameterFilter {
                $Counter -contains "\Memory\Available MBytes"
            }
        }

        It "Should support custom iteration count" {
            Watch-SystemResources -Iterations 3

            Should -Invoke Get-Counter -ModuleName PC-AI.Performance -Times 3
        }

        It "Should support custom interval" {
            Watch-SystemResources -Iterations 2 -IntervalSeconds 5

            Should -Invoke Start-Sleep -ModuleName PC-AI.Performance -ParameterFilter {
                $Seconds -eq 5
            }
        }
    }

    Context "When performance counters are unavailable" {
        BeforeAll {
            Mock Get-Counter { throw "Performance counter not found" } -ModuleName PC-AI.Performance
        }

        It "Should handle counter errors" {
            { Watch-SystemResources -Iterations 1 -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Optimize-Disks" -Tag 'Unit', 'Performance', 'Slow', 'RequiresAdmin' {
    Context "When optimizing SSD drives" {
        BeforeAll {
            Mock Get-Volume {
                [PSCustomObject]@{
                    DriveLetter = 'C'
                    FileSystem = 'NTFS'
                    DriveType = 'Fixed'
                }
            } -ModuleName PC-AI.Performance

            Mock Get-PhysicalDisk {
                [PSCustomObject]@{
                    MediaType = 'SSD'
                    DeviceId = 0
                }
            } -ModuleName PC-AI.Performance

            Mock Optimize-Volume {} -ModuleName PC-AI.Performance
        }

        It "Should run TRIM on SSD" {
            Optimize-Disks -DriveLetter 'C'

            Should -Invoke Optimize-Volume -ModuleName PC-AI.Performance -ParameterFilter {
                $ReTrim -eq $true
            }
        }

        It "Should not defragment SSD" {
            Optimize-Disks -DriveLetter 'C'

            Should -Invoke Optimize-Volume -ModuleName PC-AI.Performance -Times 0 -ParameterFilter {
                $Defrag -eq $true
            }
        }
    }

    Context "When optimizing HDD drives" {
        BeforeAll {
            Mock Get-Volume {
                [PSCustomObject]@{
                    DriveLetter = 'D'
                    FileSystem = 'NTFS'
                    DriveType = 'Fixed'
                }
            } -ModuleName PC-AI.Performance

            Mock Get-PhysicalDisk {
                [PSCustomObject]@{
                    MediaType = 'HDD'
                    DeviceId = 1
                }
            } -ModuleName PC-AI.Performance

            Mock Optimize-Volume {} -ModuleName PC-AI.Performance
        }

        It "Should defragment HDD" {
            Optimize-Disks -DriveLetter 'D'

            Should -Invoke Optimize-Volume -ModuleName PC-AI.Performance -ParameterFilter {
                $Defrag -eq $true
            }
        }

        It "Should not TRIM HDD" {
            Optimize-Disks -DriveLetter 'D'

            Should -Invoke Optimize-Volume -ModuleName PC-AI.Performance -Times 0 -ParameterFilter {
                $ReTrim -eq $true
            }
        }
    }

    Context "When not running as Administrator" {
        BeforeAll {
            Mock Optimize-Volume { throw "Access denied" } -ModuleName PC-AI.Performance
        }

        It "Should require Administrator privileges" {
            { Optimize-Disks -DriveLetter 'C' -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When AllDrives switch is used" {
        BeforeAll {
            Mock Get-Volume {
                @(
                    [PSCustomObject]@{ DriveLetter = 'C'; FileSystem = 'NTFS'; DriveType = 'Fixed' }
                    [PSCustomObject]@{ DriveLetter = 'D'; FileSystem = 'NTFS'; DriveType = 'Fixed' }
                )
            } -ModuleName PC-AI.Performance

            Mock Get-PhysicalDisk {
                [PSCustomObject]@{ MediaType = 'SSD'; DeviceId = 0 }
            } -ModuleName PC-AI.Performance

            Mock Optimize-Volume {} -ModuleName PC-AI.Performance
        }

        It "Should optimize all fixed drives" {
            Optimize-Disks -AllDrives

            Should -Invoke Optimize-Volume -ModuleName PC-AI.Performance -Times 2
        }
    }
}

AfterAll {
    Remove-Module PC-AI.Performance -Force -ErrorAction SilentlyContinue
    Remove-Module MockData -Force -ErrorAction SilentlyContinue
}
