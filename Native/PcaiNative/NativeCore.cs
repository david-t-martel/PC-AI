using System.Runtime.InteropServices;

namespace PcaiNative;

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

    /// <summary>
    /// Returns WSL/VMM health status as JSON.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_get_vmm_health_json();

    /// <summary>
    /// Returns the full diagnostic context for LLM ingestion as JSON.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_query_full_context_json();

    /// <summary>
    /// Assembles a prompt from a template and variables natively.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern PcaiStringBuffer pcai_query_prompt_assembly(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? template,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? jsonVars);

    /// <summary>
    /// Returns deep USB diagnostics as JSON via SetupAPI.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_get_usb_deep_diagnostics_json();

    /// <summary>
    /// Returns network throughput and protocol stats as JSON via IPHelper.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_get_network_throughput_json();

    /// <summary>
    /// Returns detailed process history as JSON via Psapi.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_get_process_history_json();

    /// <summary>
    /// Returns human-readable information for a Windows CM problem code.
    /// </summary>
    [DllImport(CoreDll, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr pcai_get_usb_problem_info(uint code);
}
