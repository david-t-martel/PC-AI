using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PcaiNative;

/// <summary>
/// Status codes returned by PCAI native operations.
/// Must match the Rust PcaiStatus enum exactly.
/// </summary>
public enum PcaiStatus : uint
{
    Success = 0,
    InvalidArgument = 1,
    NullPointer = 2,
    InvalidUtf8 = 3,
    PathNotFound = 4,
    PermissionDenied = 5,
    IoError = 6,
    Cancelled = 7,
    Timeout = 8,
    InternalError = 9,
    NotImplemented = 10,
    OutOfMemory = 11,
    JsonError = 12,
    Unknown = 255
}

/// <summary>
/// Generic result structure for operations that process items.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct PcaiResult
{
    public PcaiStatus Status;
    public ulong Processed;
    public ulong Matched;
    public ulong Errors;
    public ulong ElapsedMs;

    public readonly bool IsSuccess => Status == PcaiStatus.Success;
}

/// <summary>
/// String buffer for receiving string data from native code.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public struct PcaiStringBuffer
{
    public PcaiStatus Status;
    public IntPtr Data;
    public UIntPtr Length;

    public readonly bool IsValid => Status == PcaiStatus.Success && Data != IntPtr.Zero;

    /// <summary>
    /// Converts the native string buffer to a managed string.
    /// Uses UTF-8 encoding to match Rust string representation.
    /// </summary>
    public readonly string? ToManagedString()
    {
        if (!IsValid) return null;
        return Marshal.PtrToStringUTF8(Data);
    }
}

/// <summary>
/// Core P/Invoke declarations for pcai_core_lib.dll
/// </summary>
internal static partial class NativeCore
{
    private const string CoreDll = "pcai_core_lib.dll";

    /// <summary>
    /// Returns the library version string.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_core_version();

    /// <summary>
    /// Returns a magic number to verify DLL is loaded correctly.
    /// Expected value: 0x50CA1 (330913)
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint pcai_core_test();

    /// <summary>
    /// Frees a string allocated by a PCAI function.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void pcai_free_string(IntPtr buffer);

    /// <summary>
    /// Copies a string (for testing string allocation).
    /// Uses UTF-8 marshaling to match Rust string representation.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_string_copy([MarshalAs(UnmanagedType.LPUTF8Str)] string? input);

    /// <summary>
    /// Returns the number of logical CPU cores.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint pcai_cpu_count();

    /// <summary>
    /// Returns a description for a status code.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_status_description(PcaiStatus status);

    /// <summary>
    /// Frees a string buffer.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void pcai_free_string_buffer(ref PcaiStringBuffer buffer);

    /// <summary>
    /// Extracts JSON from a markdown-formatted string.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_extract_json([MarshalAs(UnmanagedType.LPUTF8Str)] string? input);

    /// <summary>
    /// Validates if a string is valid JSON.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern bool pcai_is_valid_json([MarshalAs(UnmanagedType.LPUTF8Str)] string? input);

    /// <summary>
    /// Searches for files matching a glob pattern.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern PcaiStringBuffer pcai_find_files(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? rootPath,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? pattern,
        ulong maxResults);

    /// <summary>
    /// Searches file contents for a regex pattern.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern PcaiStringBuffer pcai_search_content(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? rootPath,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? pattern,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? filePattern,
        ulong maxResults,
        uint contextLines);

    /// <summary>
    /// Finds duplicate files using parallel SHA-256.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern PcaiStringBuffer pcai_find_duplicates(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? rootPath,
        ulong minSize,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? includePattern,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? excludePattern);

    /// <summary>
    /// Queries comprehensive system information.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern PcaiStringBuffer pcai_query_system_info();

    /// <summary>
    /// Queries hardware metrics (CPU usage, temps).
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern PcaiStringBuffer pcai_query_hardware_metrics();

    /// <summary>
    /// Estimates the number of tokens in a string for Gemma-like models.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern UIntPtr pcai_estimate_tokens([MarshalAs(UnmanagedType.LPUTF8Str)] string? text);

    /// <summary>
    /// Enforces a system resource safety cap (e.g. 0.8 / 80%).
    /// Returns 1 for safe, 0 for unsafe.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int pcai_check_resource_safety(float gpuLimit);

    /// <summary>
    /// Returns high-fidelity system telemetry as JSON.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_get_system_telemetry_json();
}

/// <summary>
/// High-level wrapper for PCAI Core functionality.
/// </summary>
public static class PcaiCore
{
    // Magic number expected from pcai_core_test()
    // Value 0x50434149 spells "PCAI" in ASCII hex
    private const uint ExpectedMagicNumber = 0x5043_4149;

    // Thread-safe lazy initialization for availability check
    private static readonly Lazy<bool> _isAvailable = new(() =>
    {
        try
        {
            var result = NativeCore.pcai_core_test();
            return result == ExpectedMagicNumber;
        }
        catch
        {
            return false;
        }
    });

    // Thread-safe lazy initialization for version string
    private static readonly Lazy<string> _version = new(() =>
    {
        try
        {
            var ptr = NativeCore.pcai_core_version();
            return Marshal.PtrToStringUTF8(ptr) ?? "unknown";
        }
        catch
        {
            return "unavailable";
        }
    });

    /// <summary>
    /// Gets whether the native library is available and functional.
    /// </summary>
    public static bool IsAvailable => _isAvailable.Value;

    /// <summary>
    /// Gets the native library version.
    /// </summary>
    public static string Version => _version.Value;

    /// <summary>
    /// Gets the number of logical CPU cores reported by the native library.
    /// </summary>
    public static uint CpuCount
    {
        get
        {
            try
            {
                return NativeCore.pcai_cpu_count();
            }
            catch
            {
                return (uint)Environment.ProcessorCount;
            }
        }
    }

    /// <summary>
    /// Gets a human-readable description for a status code.
    /// </summary>
    public static string GetStatusDescription(PcaiStatus status)
    {
        try
        {
            var ptr = NativeCore.pcai_status_description(status);
            return Marshal.PtrToStringUTF8(ptr) ?? status.ToString();
        }
        catch
        {
            return status.ToString();
        }
    }

    /// <summary>
    /// Tests string allocation round-trip with the native library.
    /// </summary>
    public static string? TestStringCopy(string input)
    {
        if (!IsAvailable) return null;

        var ptr = NativeCore.pcai_string_copy(input);
        if (ptr == IntPtr.Zero) return null;

        try
        {
            return Marshal.PtrToStringUTF8(ptr);
        }
        finally
        {
            NativeCore.pcai_free_string(ptr);
        }
    }

    /// <summary>
    /// Extracts JSON from a markdown-formatted string using high-performance native logic.
    /// </summary>
    public static string? ExtractJson(string input)
    {
        if (!IsAvailable) return null;

        var ptr = NativeCore.pcai_extract_json(input);
        if (ptr == IntPtr.Zero) return null;

        try
        {
            return Marshal.PtrToStringUTF8(ptr);
        }
        finally
        {
            NativeCore.pcai_free_string(ptr);
        }
    }

    /// <summary>
    /// Validates if a string is valid JSON using native logic.
    /// </summary>
    public static bool IsValidJson(string input)
    {
        if (!IsAvailable) return false;
        return NativeCore.pcai_is_valid_json(input);
    }

    /// <summary>
    /// Searches for files matching a glob pattern using native traversal.
    /// </summary>
    public static string? FindFiles(string rootPath, string pattern, ulong maxResults = 0)
    {
        if (!IsAvailable) return null;
        var buffer = NativeCore.pcai_find_files(rootPath, pattern, maxResults);
        try { return buffer.ToManagedString(); }
        finally { NativeCore.pcai_free_string_buffer(ref buffer); }
    }

    /// <summary>
    /// Searches file contents using parallel native regex matching.
    /// </summary>
    public static string? SearchContent(string rootPath, string pattern, string? filePattern = null, ulong maxResults = 0, uint contextLines = 0)
    {
        if (!IsAvailable) return null;
        var buffer = NativeCore.pcai_search_content(rootPath, pattern, filePattern, maxResults, contextLines);
        try { return buffer.ToManagedString(); }
        finally { NativeCore.pcai_free_string_buffer(ref buffer); }
    }

    /// <summary>
    /// Finds duplicate files using parallel native hashing.
    /// </summary>
    public static string? FindDuplicates(string rootPath, ulong minSize = 0, string? includePattern = null, string? excludePattern = null)
    {
        if (!IsAvailable) return null;
        var buffer = NativeCore.pcai_find_duplicates(rootPath, minSize, includePattern, excludePattern);
        try { return buffer.ToManagedString(); }
        finally { NativeCore.pcai_free_string_buffer(ref buffer); }
    }

    /// <summary>
    /// Queries comprehensive system information natively.
    /// </summary>
    public static string? QuerySystemInfo()
    {
        if (!IsAvailable) return null;
        var buffer = NativeCore.pcai_query_system_info();
        try { return buffer.ToManagedString(); }
        finally { NativeCore.pcai_free_string_buffer(ref buffer); }
    }

    /// <summary>
    /// Queries hardware metrics natively.
    /// </summary>
    public static string? QueryHardwareMetrics()
    {
        if (!IsAvailable) return null;
        var buffer = NativeCore.pcai_query_hardware_metrics();
        try { return buffer.ToManagedString(); }
        finally { NativeCore.pcai_free_string_buffer(ref buffer); }
    }

    /// <summary>
    /// Estimates the number of tokens in a string for Gemma-like models natively.
    /// </summary>
    public static ulong EstimateTokens(string text)
    {
        if (!IsAvailable) return 0;
        return (ulong)NativeCore.pcai_estimate_tokens(text);
    }

    /// <summary>
    /// Checks if system resources are within safety limits (e.g. 80% load).
    /// </summary>
    public static bool CheckResourceSafety(float gpuLimit = 0.8f)
    {
        if (!IsAvailable) return true; // Fail safe if lib unavailable
        return NativeCore.pcai_check_resource_safety(gpuLimit) != 0;
    }

    /// <summary>
    /// Gets high-fidelity system telemetry as JSON using native core.
    /// </summary>
    public static string? GetSystemTelemetryJson()
    {
        if (!IsAvailable) return null;
        var ptr = NativeCore.pcai_get_system_telemetry_json();
        if (ptr == IntPtr.Zero) return null;
        try { return Marshal.PtrToStringUTF8(ptr); }
        finally { NativeCore.pcai_free_string(ptr); }
    }

    /// <summary>
    /// Gets diagnostic information about the native library.
    /// </summary>
    public static NativeDiagnostics GetDiagnostics()
    {
        return new NativeDiagnostics
        {
            IsAvailable = IsAvailable,
            Version = Version,
            CpuCount = CpuCount,
            Platform = Environment.Is64BitProcess ? "x64" : "x86",
            DotNetVersion = Environment.Version.ToString()
        };
    }
}

/// <summary>
/// Diagnostic information about the native library.
/// </summary>
public sealed class NativeDiagnostics
{
    [JsonPropertyName("isAvailable")]
    public bool IsAvailable { get; init; }

    [JsonPropertyName("version")]
    public string Version { get; init; } = "";

    [JsonPropertyName("cpuCount")]
    public uint CpuCount { get; init; }

    [JsonPropertyName("platform")]
    public string Platform { get; init; } = "";

    [JsonPropertyName("dotNetVersion")]
    public string DotNetVersion { get; init; } = "";

    public string ToJson() => JsonSerializer.Serialize(this, new JsonSerializerOptions
    {
        WriteIndented = true
    });
}
