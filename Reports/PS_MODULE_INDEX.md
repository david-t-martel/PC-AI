# PS_MODULE_INDEX

Generated: 2026-01-27 04:13:42

## PC-AI.Acceleration.psm1
- Compare-ToolPerformance: Compares performance between Rust tools and PowerShell equivalents
- Find-DuplicatesFast: Fast duplicate file detection using parallel hashing and fd
- Find-FilesFast: Fast file finding using fd
- Get-DiskUsageFast: Fast disk usage analysis using dust or parallel enumeration
- Get-FileHashParallel: Computes file hashes in parallel using PowerShell 7+ native parallelism
- Get-ProcessesFast: Fast process listing using procs
- Get-RustToolStatus: Reports the status of available Rust acceleration tools
- Measure-CommandPerformance: Benchmarks command performance using hyperfine or native measurement
- Search-ContentFast: Fast content search using ripgrep with parallel fallback
- Search-LogsFast: Fast log file searching using ripgrep

## PC-AI.Cleanup.psm1
- Clear-TempFiles: Safely cleans temporary files from common system locations.
- Find-DuplicateFiles: Finds duplicate files by content hash in specified directory.
- Get-PathDuplicates: Analyzes PATH environment variable for duplicates and non-existent entries.
- Invoke-NukeNulCleanup: Runs the NukeNul reserved filename cleanup tool and returns JSON results.
- Repair-MachinePath: Repairs PATH environment variable by removing duplicates and invalid entries.

## PC-AI.Hardware.psm1
- Get-DeviceErrors: Gets devices with errors from Device Manager
- Get-DiskHealth: Gets disk health status including SMART information
- Get-NetworkAdapters: Gets physical network adapter status
- Get-SystemEvents: Gets system events related to disk and USB devices
- Get-UsbStatus: Gets USB device and controller status
- New-DiagnosticReport: Generates a comprehensive hardware diagnostic report

## PC-AI.LLM.psm1
- Get-LLMStatus: Checks the status of Ollama LLM service and available models
- Get-SystemInfoTool: Active system interrogation tool for the AI agent.
- Invoke-DocSearch: Search Microsoft and manufacturer documentation for technical details.
- Invoke-FunctionGemmaReAct: Uses FunctionGemma (via vLLM OpenAI API) to plan tool calls and optionally executes them.
- Invoke-LLMChat
- Invoke-LLMChatTui
- Invoke-NativeSearch: Invokes native high-performance search operations for LLM analysis
- Invoke-PCDiagnosis: Analyzes PC diagnostic reports using LLM
- Invoke-SmartDiagnosis
- Send-OllamaRequest: Sends a request to the Ollama API for text generation
- Set-LLMConfig: Configures LLM module settings
- Set-LLMProviderOrder

## PC-AI.Network.psm1
- Get-NetworkDiagnostics: Performs comprehensive network stack analysis
- Optimize-VSock: Optimizes VSock and TCP settings for WSL2 performance (Requires Administrator)
- Test-WSLConnectivity: Tests connectivity between Windows and WSL
- Watch-VSockPerformance: Real-time VSock and network interface performance monitoring

## PC-AI.Performance.psm1
- Get-DiskSpace: Analyzes disk space usage on all or specified drives.
- Get-ProcessPerformance: Gets top processes sorted by CPU or memory usage.
- Optimize-Disks: Optimizes disks using TRIM for SSDs or defragmentation for HDDs.
- Watch-SystemResources: Real-time monitoring of CPU, memory, and disk I/O.

## PC-AI.USB.psm1
- Dismount-UsbFromWSL: Detaches a USB device from WSL
- Get-UsbDeviceList: Lists USB devices available for WSL attachment
- Get-UsbWSLStatus: Gets complete USB/WSL status
- Invoke-UsbBind: Binds a USB device for WSL sharing
- Mount-UsbToWSL: Attaches a USB device to WSL

## PC-AI.Virtualization.psm1
- Backup-WSLConfig: Creates a backup of .wslconfig
- Enable-WSLSystemd: Enables systemd in a WSL distribution by updating /etc/wsl.conf.
- Get-DockerStatus: Gets Docker Desktop status and configuration
- Get-HVSockProxyStatus
- Get-HyperVStatus: Gets Hyper-V status and configuration
- Get-WSLEnvironmentHealth: Comprehensive health check for WSL, Docker, and VSock bridges
- Get-WSLStatus: Gets comprehensive WSL status information
- Get-WSLVsockBridgeStatus
- Install-HVSockProxy
- Install-WSLVsockBridge
- Invoke-PcaiServiceHost
- Invoke-WSLDockerHealthCheck
- Invoke-WSLNetworkToolkit: Wrapper for the external WSL network toolkit script.
- Optimize-ModelHost: Optimizes the model host (WSL) for vLLM performance and resource safety.
- Optimize-WSLConfig: Optimizes .wslconfig for performance
- Register-HVSockServices: Registers Hyper-V socket (HVSOCK) services for WSL guests.
- Repair-WSLNetworking: Repairs WSL networking issues
- Set-PCaiServiceState
- Set-WSLDefenderExclusion: Adds Windows Defender exclusions for WSL
- Start-HVSockProxy
- Stop-HVSockProxy


