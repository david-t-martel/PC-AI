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
