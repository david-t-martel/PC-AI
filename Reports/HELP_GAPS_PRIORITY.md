# Help Documentation Gaps

Generated: 2026-01-30 12:57:36

## Summary

- **Total functions**: 110
- **Missing help**: 57
- **Coverage**: 48.2%

## Priority Order

### PC-AI.LLM (22 functions)

**No help documentation (17):**

- [ ] `Build-DiagnosticSummary` - Missing 1 parameters: DiagnosticData
- [ ] `Format-ContentSearchResultForLLM` - Missing 1 parameters: NativeResult
- [ ] `Format-DuplicateResultForLLM` - Missing 1 parameters: NativeResult
- [ ] `Format-FileSearchResultForLLM` - Missing 1 parameters: NativeResult
- [ ] `Get-LLMStatus` - Missing 3 parameters: IncludeLMStudio, IncludeVLLM, TestConnection
- [ ] `Get-SystemInfoTool` - Missing 2 parameters: Category, Detail
- [ ] `Invoke-DocSearch` - Missing 2 parameters: Query, Source
- [ ] `Invoke-FunctionGemmaReAct` - Missing 12 parameters: Prompt, BaseUrl, Model, ToolsPath, ExecuteTools, ReturnFinal, MaxToolCalls, ResultLimit, TimeoutSeconds, ShowProgress, ShowMetrics, ProgressIntervalSeconds
- [ ] `Invoke-LLMChat` - Missing 17 parameters: Message, Model, System, Temperature, MaxTokens, TimeoutSeconds, Interactive, ToJson, History, Provider, UseRouter, RouterMode, Stream, ShowProgress, ShowMetrics, ProgressIntervalSeconds, ResultLimit
- [ ] `Invoke-LLMChatTui` - Missing 1 parameters: Arguments
- [ ] `Invoke-LogSearch` - Missing 6 parameters: Pattern, RootPath, FilePattern, CaseSensitive, ContextLines, MaxMatches
- [ ] `Invoke-PCDiagnosis` - Missing 15 parameters: DiagnosticReportPath, ReportText, Model, Temperature, IncludeRawResponse, SaveReport, OutputPath, TimeoutSeconds, UseRouter, RouterBaseUrl, RouterModel, RouterToolsPath, RouterMaxCalls, RouterExecuteTools, EnforceJson
- [ ] `Invoke-PowerShellContentSearch` - Missing 5 parameters: Path, Pattern, FilePattern, MaxResults, ContextLines
- [ ] `Invoke-PowerShellDuplicates` - Missing 3 parameters: Path, MinimumSize, MaxResults
- [ ] `Invoke-PowerShellFileSearch` - Missing 3 parameters: Path, Pattern, MaxResults
- [ ] `Send-OllamaRequest` - Missing 9 parameters: Prompt, Model, System, Temperature, MaxTokens, Stream, TimeoutSeconds, MaxRetries, RetryDelaySeconds
- [ ] `Set-LLMConfig` - Missing 7 parameters: DefaultModel, OllamaApiUrl, LMStudioApiUrl, OllamaPath, DefaultTimeout, ShowConfig, Reset

**Partial help documentation (5):**

- [ ] `Invoke-FunctionGemmaChat` - Missing 2 parameters: Messages, Tools
- [ ] `Invoke-LLMChatRouted` - Missing 1 parameters: EnforceJson
- [ ] `Invoke-NativeSearch` - Missing 1 parameters: FilePattern
- [ ] `Invoke-SmartDiagnosis` - Missing 8 parameters: Path, AnalysisType, Model, SaveReport, OutputPath, SkipLLMAnalysis, OllamaBaseUrl, TimeoutSeconds
- [ ] `Set-LLMProviderOrder` - Missing 1 parameters: Order

### PC-AI.Acceleration (32 functions)

**No help documentation (23):**

- [ ] `Compare-ContentSearchPerformance` - Missing 2 parameters: Path, Iterations
- [ ] `Compare-FileSearchPerformance` - Missing 2 parameters: Path, Iterations
- [ ] `Compare-HashPerformance` - Missing 2 parameters: Path, Iterations
- [ ] `Compare-ProcessListPerformance` - Missing 1 parameters: Iterations
- [ ] `Convert-SizeToBytes` - Missing 1 parameters: Size
- [ ] `Find-WithFd` - Missing 9 parameters: Path, Pattern, Extension, Type, MaxDepth, Hidden, Exclude, FullPath, FdPath
- [ ] `Find-WithFdForDuplicates` - Missing 4 parameters: Path, Include, Exclude, FdPath
- [ ] `Find-WithGetChildItem` - Missing 8 parameters: Path, Pattern, Extension, Type, MaxDepth, Hidden, Exclude, FullPath
- [ ] `Format-ByteSize` - Missing 1 parameters: Bytes
- [ ] `Get-AcceleratedFunction` - Missing 1 parameters: Tool
- [ ] `Get-DiskUsageParallel` - Missing 3 parameters: Path, Depth, ThrottleLimit
- [ ] `Get-DiskUsageWithDust` - Missing 3 parameters: Path, Depth, DustPath
- [ ] `Get-ProcessesParallel` - Missing 6 parameters: Name, SortBy, Top, Tree, Watch, RawOutput
- [ ] `Get-ProcessesWithProcs` - Missing 7 parameters: Name, SortBy, Top, Tree, Watch, RawOutput, ProcsPath
- [ ] `Measure-WithHyperfine` - Missing 6 parameters: Command, Iterations, Warmup, Name, Shell, HyperfinePath
- [ ] `Measure-WithNative` - Missing 4 parameters: Command, Iterations, Warmup, Name
- [ ] `Search-WithParallelSelectString` - Missing 12 parameters: Path, Pattern, LiteralPattern, FilePattern, Context, CaseSensitive, WholeWord, Invert, MaxResults, FilesOnly, ThrottleLimit, SearchPattern
- [ ] `Search-WithRipgrep` - Missing 8 parameters: Path, Pattern, Include, Context, CaseSensitive, MaxCount, CountOnly, RgPath
- [ ] `Search-WithRipgrepAdvanced` - Missing 13 parameters: Path, Pattern, LiteralPattern, FilePattern, Context, CaseSensitive, WholeWord, Invert, MaxResults, FilesOnly, ThrottleLimit, SearchPattern, RgPath
- [ ] `Search-WithSelectString` - Missing 7 parameters: Path, Pattern, Include, Context, CaseSensitive, MaxCount, CountOnly
- [ ] `Select-TopResults` - Missing 2 parameters: InputObject, Top
- [ ] `Sort-DiskUsageResults` - Missing 2 parameters: InputObject, SortBy
- [ ] `Test-RustToolAvailable` - Missing 1 parameters: Tool

**Partial help documentation (9):**

- [ ] `Compare-ToolPerformance` - Missing 1 parameters: Detailed
- [ ] `Find-DuplicatesFast` - Missing 2 parameters: MaximumSize, ShowProgress
- [ ] `Find-FilesFast` - Missing 1 parameters: FullPath
- [ ] `Get-DiskUsageFast` - Missing 1 parameters: ThrottleLimit
- [ ] `Get-FileHashParallel` - Missing 2 parameters: MinimumSize, MaximumSize
- [ ] `Get-ProcessesFast` - Missing 1 parameters: RawOutput
- [ ] `Get-UnifiedHardwareReportJson` - Missing 1 parameters: Verbosity
- [ ] `Search-ContentFast` - Missing 4 parameters: CaseSensitive, MaxResults, FilesOnly, ThrottleLimit
- [ ] `Search-LogsFast` - Missing 1 parameters: CountOnly

### PC-AI.Virtualization (18 functions)

**No help documentation (6):**

- [ ] `Get-StatusColor` - Missing 1 parameters: Status
- [ ] `Test-DockerHealth` - Missing 2 parameters: Distribution, AutoRecover
- [ ] `Test-RAGRedisHealth` - Missing 2 parameters: AutoRecover, ComposePath
- [ ] `Test-VSockBridgeHealth` - Missing 2 parameters: Distribution, AutoRecover
- [ ] `Test-WSLHealth` - Missing 2 parameters: Distribution, AutoRecover
- [ ] `Test-WSLNetworkHealth` - Missing 1 parameters: Distribution

**Partial help documentation (12):**

- [ ] `Get-HVSockProxyStatus` - Missing 1 parameters: StatePath
- [ ] `Get-PcaiServiceHealth` - Missing 3 parameters: Distribution, OllamaBaseUrl, vLLMBaseUrl
- [ ] `Get-WSLVsockBridgeStatus` - Missing 1 parameters: Distribution
- [ ] `Install-HVSockProxy` - Missing 2 parameters: Installer, Force
- [ ] `Install-WSLVsockBridge` - Missing 6 parameters: Distribution, BridgeScriptPath, ServiceFilePath, ConfigPath, EnableService, StartService
- [ ] `Invoke-PcaiServiceHost` - Missing 2 parameters: Args, HostPath
- [ ] `Invoke-WSLDockerHealthCheck` - Missing 4 parameters: ScriptPath, AutoRecover, Verbose, Quick
- [ ] `Invoke-WSLNetworkToolkit` - Missing 12 parameters: Optimize, ApplyConfig, TestNetworkingMode, NetworkingMode, FixDns, RestartWsl, ResetAdapters, ResetWinsock, RestartHns, RestartWslService, DisableVmqOnWsl, Force
- [ ] `Register-HVSockServices` - Missing 2 parameters: ConfigPath, Force
- [ ] `Set-PCaiServiceState` - Missing 2 parameters: Name, Action
- [ ] `Start-HVSockProxy` - Missing 4 parameters: ConfigPath, StatePath, Force, RegisterServices
- [ ] `Stop-HVSockProxy` - Missing 1 parameters: StatePath

### PC-AI.Cleanup (5 functions)

**No help documentation (5):**

- [ ] `Clear-TempFiles` - Missing 5 parameters: Target, OlderThanDays, IncludePrefetch, IncludeWindowsUpdate, Force
- [ ] `Find-DuplicateFiles` - Missing 8 parameters: Path, Recurse, MinimumSize, MaximumSize, Algorithm, Include, Exclude, ShowProgress
- [ ] `Get-PathDuplicates` - Missing 2 parameters: Target, IncludeProcess
- [ ] `Invoke-NukeNulCleanup` - Missing 3 parameters: Path, ExePath, Force
- [ ] `Repair-MachinePath` - Missing 5 parameters: Target, RemoveNonExistent, NormalizeSlashes, Force, BackupPath

### PC-AI.Performance (4 functions)

**No help documentation (4):**

- [ ] `Get-DiskSpace` - Missing 4 parameters: DriveLetter, ThresholdPercent, IncludeRemovable, IncludeNetwork
- [ ] `Get-ProcessPerformance` - Missing 6 parameters: Top, SortBy, IncludeSystemProcesses, ExcludeIdle, MinimumCpuPercent, MinimumMemoryMB
- [ ] `Optimize-Disks` - Missing 4 parameters: DriveLetter, Force, Priority, AnalyzeOnly
- [ ] `Watch-SystemResources` - Missing 7 parameters: RefreshInterval, Duration, IncludeTopProcesses, TopProcessCount, OutputMode, WarningThreshold, CriticalThreshold

### PC-AI.USB (1 functions)

**Partial help documentation (1):**

- [ ] `Get-UsbDeviceList` - Missing 1 parameters: Filter

## Recommendations

### High Priority (Complete missing documentation)

1. **PC-AI.LLM module** - Core functionality for LLM integration
   - Focus on Invoke-LLMChat, Invoke-FunctionGemmaReAct, and routing functions first
   - These are frequently used public interfaces

2. **PC-AI.Cleanup module** - All functions lack documentation
   - Clear-TempFiles, Repair-MachinePath, Find-DuplicateFiles should be documented first

3. **PC-AI.Performance module** - All functions lack documentation
   - Watch-SystemResources, Get-ProcessPerformance are key diagnostic functions

### Medium Priority (Partial documentation)

1. **PC-AI.Acceleration module** - Multiple functions need completion
   - Helper functions like Convert-SizeToBytes, Format-ByteSize need documentation
   - Backend implementations (e.g., Get-ProcessesWithProcs) can be lower priority

2. **PC-AI.Virtualization module** - Multiple functions need completion
   - Priority: Install-WSLVsockBridge, Start-HVSockProxy configuration functions
   - Lower: Internal health check helpers like Get-StatusColor

### Documentation Standards

When adding help documentation:
- Use comment-based help with .SYNOPSIS, .DESCRIPTION, .PARAMETER, .EXAMPLE
- Include at least one example showing common usage
- Document parameter validation constraints
- Specify default values where applicable
- Add .NOTES section for version history or special requirements

