@{
    Run = @{
        Path = @(
            'Unit'
            'Integration'
        )
        Exit = $false
        PassThru = $true
    }

    CodeCoverage = @{
        Enabled = $false  # Enable via .pester.ps1 -Coverage flag
        OutputFormat = 'JaCoCoXml'
        OutputPath = 'coverage.xml'
        Path = @(
            '..\Modules\PC-AI.Hardware\**\*.ps1'
            '..\Modules\PC-AI.Virtualization\**\*.ps1'
            '..\Modules\PC-AI.USB\**\*.ps1'
            '..\Modules\PC-AI.Cleanup\**\*.ps1'
            '..\Modules\PC-AI.Performance\**\*.ps1'
            '..\Modules\PC-AI.LLM\**\*.ps1'
            '..\Modules\PC-AI.Network\**\*.ps1'
        )
        ExcludeTests = $true
        RecursePaths = $true
        CoveragePercentTarget = 85
    }

    TestResult = @{
        Enabled = $false  # Enable via .pester.ps1 -CI flag
        OutputFormat = 'NUnitXml'
        OutputPath = 'test-results.xml'
        TestSuiteName = 'PC_AI_Test_Suite'
    }

    Output = @{
        Verbosity = 'Detailed'  # Detailed for local dev, Normal for CI
        StackTraceVerbosity = 'Filtered'
        CIFormat = 'Auto'
    }

    Filter = @{
        Tag = @()
        ExcludeTag = @()
        Line = @()
    }

    Should = @{
        ErrorAction = 'Stop'
    }

    Debug = @{
        ShowFullErrors = $true
        WriteDebugMessages = $false
        WriteDebugMessagesFrom = @()
        ShowNavigationMarkers = $false
    }
}
