# API_SIGNATURE_REPORT

Generated: 2026-01-30 21:06:26

PowerShell functions: 112
Missing help blocks: 60
C# DllImports: 42
Missing Rust exports: 7

## Missing help parameters
- Compare-ToolPerformance: missing Detailed
- Compare-FileSearchPerformance: missing Path, Iterations
- Compare-ContentSearchPerformance: missing Path, Iterations
- Compare-ProcessListPerformance: missing Iterations
- Compare-HashPerformance: missing Path, Iterations
- Find-DuplicatesFast: missing MaximumSize, ShowProgress
- Find-WithFdForDuplicates: missing Path, Include, Exclude, FdPath
- Find-FilesFast: missing FullPath
- Find-WithFd: missing Path, Pattern, Extension, Type, MaxDepth, Hidden, Exclude, FullPath, FdPath
- Find-WithGetChildItem: missing Path, Pattern, Extension, Type, MaxDepth, Hidden, Exclude, FullPath
- Get-DiskUsageFast: missing ThrottleLimit
- Convert-SizeToBytes: missing Size
- Get-DiskUsageWithDust: missing Path, Depth, DustPath
- Get-DiskUsageParallel: missing Path, Depth, ThrottleLimit
- Format-ByteSize: missing Bytes
- Sort-DiskUsageResults: missing InputObject, SortBy
- Select-TopResults: missing InputObject, Top
- Get-FileHashParallel: missing MinimumSize, MaximumSize
- Get-ProcessesFast: missing RawOutput
- Get-ProcessesWithProcs: missing Name, SortBy, Top, Tree, Watch, RawOutput, ProcsPath
- Get-ProcessesParallel: missing Name, SortBy, Top, Tree, Watch, RawOutput
- Get-AcceleratedFunction: missing Tool
- Test-RustToolAvailable: missing Tool
- Get-UnifiedHardwareReportJson: missing Verbosity
- Measure-WithHyperfine: missing Command, Iterations, Warmup, Name, Shell, HyperfinePath
- Measure-WithNative: missing Command, Iterations, Warmup, Name
- Search-ContentFast: missing CaseSensitive, MaxResults, FilesOnly, ThrottleLimit
- Search-WithRipgrepAdvanced: missing Path, Pattern, LiteralPattern, FilePattern, Context, CaseSensitive, WholeWord, Invert, MaxResults, FilesOnly, ThrottleLimit, SearchPattern, RgPath
- Search-WithParallelSelectString: missing Path, Pattern, LiteralPattern, FilePattern, Context, CaseSensitive, WholeWord, Invert, MaxResults, FilesOnly, ThrottleLimit, SearchPattern
- Search-LogsFast: missing CountOnly
- Search-WithRipgrep: missing Path, Pattern, Include, Context, CaseSensitive, MaxCount, CountOnly, RgPath
- Search-WithSelectString: missing Path, Pattern, Include, Context, CaseSensitive, MaxCount, CountOnly
- Clear-TempFiles: missing Target, OlderThanDays, IncludePrefetch, IncludeWindowsUpdate, Force
- Find-DuplicateFiles: missing Path, Recurse, MinimumSize, MaximumSize, Algorithm, Include, Exclude, ShowProgress
- Get-PathDuplicates: missing Target, IncludeProcess
- Invoke-NukeNulCleanup: missing Path, ExePath, Force
- Repair-MachinePath: missing Target, RemoveNonExistent, NormalizeSlashes, Force, BackupPath
- Get-LLMStatus: missing IncludeLMStudio, IncludeVLLM, TestConnection
- Get-SystemInfoTool: missing Category, Detail
- Invoke-DocSearch: missing Query, Source
- Invoke-FunctionGemmaChat: missing Messages, Tools, BaseUrl, Model, TimeoutSeconds
- Invoke-FunctionGemmaReAct: missing Prompt, BaseUrl, Model, ToolsPath, ExecuteTools, ReturnFinal, MaxToolCalls, ResultLimit, TimeoutSeconds, ShowProgress, ShowMetrics, ProgressIntervalSeconds
- Invoke-LLMChat: missing Message, Model, System, Temperature, MaxTokens, TimeoutSeconds, Interactive, ToJson, History, Provider, UseRouter, RouterMode, Stream, ShowProgress, ShowMetrics, ProgressIntervalSeconds, ResultLimit
- Invoke-LLMChatRouted: missing EnforceJson
- Invoke-LLMChatTui: missing Arguments
- Invoke-LogSearch: missing Pattern, RootPath, FilePattern, CaseSensitive, ContextLines, MaxMatches
- Invoke-NativeSearch: missing FilePattern
- Format-DuplicateResultForLLM: missing NativeResult
- Format-FileSearchResultForLLM: missing NativeResult
- Format-ContentSearchResultForLLM: missing NativeResult
- Invoke-PowerShellDuplicates: missing Path, MinimumSize, MaxResults
- Invoke-PowerShellFileSearch: missing Path, Pattern, MaxResults
- Invoke-PowerShellContentSearch: missing Path, Pattern, FilePattern, MaxResults, ContextLines
- Invoke-PCDiagnosis: missing DiagnosticReportPath, ReportText, Model, Temperature, IncludeRawResponse, SaveReport, OutputPath, TimeoutSeconds, UseRouter, RouterBaseUrl, RouterModel, RouterToolsPath, RouterMaxCalls, RouterExecuteTools, EnforceJson
- Invoke-SmartDiagnosis: missing Path, AnalysisType, Model, SaveReport, OutputPath, SkipLLMAnalysis, OllamaBaseUrl, TimeoutSeconds
- Build-DiagnosticSummary: missing DiagnosticData
- Send-OllamaRequest: missing Prompt, Model, System, Temperature, MaxTokens, Stream, TimeoutSeconds, MaxRetries, RetryDelaySeconds
- Set-LLMConfig: missing DefaultModel, PcaiInferenceApiUrl, OllamaApiUrl, LMStudioApiUrl, OllamaPath, DefaultTimeout, ShowConfig, Reset
- Set-LLMProviderOrder: missing Order
- Get-DiskSpace: missing DriveLetter, ThresholdPercent, IncludeRemovable, IncludeNetwork
- Get-ProcessPerformance: missing Top, SortBy, IncludeSystemProcesses, ExcludeIdle, MinimumCpuPercent, MinimumMemoryMB
- Optimize-Disks: missing DriveLetter, Force, Priority, AnalyzeOnly
- Watch-SystemResources: missing RefreshInterval, Duration, IncludeTopProcesses, TopProcessCount, OutputMode, WarningThreshold, CriticalThreshold
- Get-UsbDeviceList: missing Filter
- Get-HVSockProxyStatus: missing StatePath
- Get-PcaiServiceHealth: missing OllamaBaseUrl, vLLMBaseUrl
- Test-WSLHealth: missing Distribution, AutoRecover
- Test-DockerHealth: missing Distribution, AutoRecover
- Test-VSockBridgeHealth: missing Distribution, AutoRecover
- Test-RAGRedisHealth: missing AutoRecover, ComposePath
- Test-WSLNetworkHealth: missing Distribution
- Get-StatusColor: missing Status
- Get-WSLVsockBridgeStatus: missing Distribution
- Install-HVSockProxy: missing Installer, Force
- Install-WSLVsockBridge: missing Distribution, BridgeScriptPath, ServiceFilePath, ConfigPath, EnableService, StartService
- Invoke-PcaiServiceHost: missing HostPath
- Start-RustInferenceServer: missing Port, ModelPath, GpuLayers, ServerArgs, NoWait
- Start-CSharpServiceHost: missing HostPath, ServerArgs, NoWait
- Invoke-WSLDockerHealthCheck: missing ScriptPath, AutoRecover, Verbose, Quick
- Invoke-WSLNetworkToolkit: missing Optimize, ApplyConfig, TestNetworkingMode, NetworkingMode, FixDns, RestartWsl, ResetAdapters, ResetWinsock, RestartHns, RestartWslService, DisableVmqOnWsl, Force
- Register-HVSockServices: missing ConfigPath, Force
- Set-PCaiServiceState: missing Name, Action
- Start-HVSockProxy: missing ConfigPath, StatePath, Force, RegisterServices
- Stop-HVSockProxy: missing StatePath

## Extra help parameters
- Search-ContentFast: extra IgnoreCase

## Missing Rust exports for C# DllImports
- pcai_delete_fs_item
- pcai_fs_version
- pcai_get_disk_usage
- pcai_get_disk_usage_json
- pcai_get_top_processes_json
- pcai_replace_in_file
- pcai_replace_in_files


