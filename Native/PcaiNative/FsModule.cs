using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PcaiNative
{
    // ============================================================================
    // JSON Results
    // ============================================================================

    public sealed class ReplaceResult
    {
        [JsonPropertyName("status")]
        public string Status { get; set; } = "";

        [JsonPropertyName("files_scanned")]
        public ulong FilesScanned { get; set; }

        [JsonPropertyName("files_changed")]
        public ulong FilesChanged { get; set; }

        [JsonPropertyName("matches_replaced")]
        public ulong MatchesReplaced { get; set; }

        [JsonPropertyName("elapsed_ms")]
        public ulong ElapsedMs { get; set; }
    }

    // ============================================================================
    // P/Invoke
    // ============================================================================

    internal static partial class NativeFs
    {
        private const string DllName = "pcai_fs.dll";

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern uint pcai_fs_version();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern PcaiStatus pcai_replace_in_file(
            [MarshalAs(UnmanagedType.LPUTF8Str)] string filePath,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string pattern,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string replacement,
            [MarshalAs(UnmanagedType.U1)] bool isRegex,
            [MarshalAs(UnmanagedType.U1)] bool backup);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern PcaiStringBuffer pcai_replace_in_files(
            [MarshalAs(UnmanagedType.LPUTF8Str)] string rootPath,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string? filePattern,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string contentPattern,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string replacement,
            [MarshalAs(UnmanagedType.U1)] bool isRegex,
            [MarshalAs(UnmanagedType.U1)] bool backup);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern PcaiStatus pcai_delete_fs_item(
            [MarshalAs(UnmanagedType.LPUTF8Str)] string path,
            [MarshalAs(UnmanagedType.U1)] bool recursive);
    }

    /// <summary>
    /// High-performance file system operations backed by Rust.
    /// </summary>
    public static class FsModule
    {
        private static readonly Lazy<bool> _isAvailable = new(() =>
        {
            try { return NativeFs.pcai_fs_version() > 0; }
            catch { return false; }
        });

        public static bool IsAvailable => _isAvailable.Value;

        /// <summary>
        /// Replace text in a single file.
        /// </summary>
        public static PcaiStatus ReplaceInFile(string filePath, string pattern, string replacement, bool isRegex = false, bool backup = false)
        {
            if (!IsAvailable) return PcaiStatus.NotImplemented;
            return NativeFs.pcai_replace_in_file(filePath, pattern, replacement, isRegex, backup);
        }

        /// <summary>
        /// Replace text in multiple files using parallel processing.
        /// </summary>
        public static ReplaceResult? ReplaceInFiles(string rootPath, string pattern, string replacement, string? filePattern = null, bool isRegex = false, bool backup = false)
        {
            if (!IsAvailable) return null;

            var buffer = NativeFs.pcai_replace_in_files(rootPath, filePattern, pattern, replacement, isRegex, backup);
            try
            {
                var json = buffer.ToManagedString();
                if (string.IsNullOrEmpty(json)) return null;
                return JsonSerializer.Deserialize<ReplaceResult>(json);
            }
            finally
            {
                NativeCore.pcai_free_string_buffer(ref buffer);
            }
        }

        /// <summary>
        /// Fast delete file or directory.
        /// </summary>
        public static PcaiStatus DeleteItem(string path, bool recursive = false)
        {
            if (!IsAvailable) return PcaiStatus.NotImplemented;
            return NativeFs.pcai_delete_fs_item(path, recursive);
        }
    }
}
