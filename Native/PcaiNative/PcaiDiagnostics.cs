using System.Text.Json;

namespace PcaiNative;

/// <summary>
/// .NET-native diagnostic collectors for optimal Windows interrogation.
/// Replaces slow PowerShell/CIM cmdlets for standard metrics.
/// </summary>
public static class PcaiDiagnostics
{
    /// <summary>
    /// Gets network interface info using .NET native APIs (Zero FFI).
    /// </summary>
    public static string GetNetworkInfoJson()
    {
        var interfaces = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces();
        var result = interfaces.Select(i => new
        {
            Name = i.Name,
            Description = i.Description,
            Status = i.OperationalStatus.ToString(),
            SpeedKbps = i.Speed / 1024,
            Type = i.NetworkInterfaceType.ToString(),
            MacAddress = i.GetPhysicalAddress().ToString()
        });

        return JsonSerializer.Serialize(result);
    }

    /// <summary>
    /// Gets process info using .NET native APIs.
    /// </summary>
    public static string GetProcessInfoJson()
    {
        var current = System.Diagnostics.Process.GetCurrentProcess();
        var all = System.Diagnostics.Process.GetProcesses();

        var result = all.Where(p => p.ProcessName.Contains("pwsh") || p.ProcessName.Contains("powershell") || p.Id == current.Id)
            .Select(p => new
            {
                Pid = p.Id,
                Name = p.ProcessName,
                MemoryMb = p.WorkingSet64 / 1024 / 1024,
                Threads = p.Threads.Count
            });

        return JsonSerializer.Serialize(result);
    }

    /// <summary>
    /// Gets a unified hardware report combining WMI configuration codes with deep native diagnostics.
    /// Supports verbosity levels to control LLM context pressure.
    /// This is the "Search Pin" logic designed to inform external LLM web searches.
    /// </summary>
    public static string GetUnifiedHardwareReportJson(DiagnosticVerbosity verbosity = DiagnosticVerbosity.Normal)
    {
        var usbDeep = PcaiCore.GetUsbDeepDiagnostics();
        var netDeep = PcaiCore.GetNetworkThroughput();

        var usbDiagnostics = !string.IsNullOrWhiteSpace(usbDeep)
            ? (object)JsonSerializer.Deserialize<JsonElement>(usbDeep!)
            : null;
        var networkDiagnostics = !string.IsNullOrWhiteSpace(netDeep)
            ? (object)JsonSerializer.Deserialize<JsonElement>(netDeep!)
            : null;

        // Apply verbosity filtering
        if (verbosity == DiagnosticVerbosity.Basic)
        {
            // In Basic mode, we might want to filter USB devices to only those WITH errors
            if (usbDiagnostics is JsonElement usbArray && usbArray.ValueKind == JsonValueKind.Array)
            {
                var failedUsb = usbArray.EnumerateArray()
                    .Where(d => d.TryGetProperty("config_error_code", out var code) && code.GetUInt32() != 0)
                    .ToList();
                usbDiagnostics = failedUsb.Count > 0 ? failedUsb : null;
            }

            // In Basic mode, we might just want a summary of network interfaces
            networkDiagnostics = "Omitted in Basic mode. Use Normal/Full for throughput data.";
        }

        // Basic WMI aggregation for "Search Pins"
        var report = new
        {
            UsbDiagnostics = usbDiagnostics,
            NetworkDiagnostics = networkDiagnostics,
            Verbosity = verbosity.ToString(),
            Timestamp = DateTime.UtcNow.ToString("o"),
            NativeVersion = PcaiCore.Version
        };

        return JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });
    }
}
