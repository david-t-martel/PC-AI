using System;
using System.Runtime.InteropServices;

namespace PcaiNative
{
    /// <summary>
    /// Disk usage statistics returned by native functions.
    /// </summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct DiskUsageStats
    {
        public PcaiStatus Status;
        public ulong TotalSizeBytes;
        public ulong TotalFiles;
        public ulong TotalDirs;
        public ulong ElapsedMs;

        public bool IsSuccess => Status == PcaiStatus.Success;
    }

    /// <summary>
    /// Process statistics returned by native functions.
    /// </summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct ProcessStats
    {
        public PcaiStatus Status;
        public uint TotalProcesses;
        public uint TotalThreads;
        public float SystemCpuUsage;
        public ulong SystemMemoryUsedBytes;
        public ulong SystemMemoryTotalBytes;
        public ulong ElapsedMs;

        public bool IsSuccess => Status == PcaiStatus.Success;

        public double MemoryUsagePercent => SystemMemoryTotalBytes > 0
            ? (double)SystemMemoryUsedBytes / SystemMemoryTotalBytes * 100.0
            : 0.0;
    }

    /// <summary>
    /// Memory statistics returned by native functions.
    /// </summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct MemoryStats
    {
        public PcaiStatus Status;
        public ulong TotalMemoryBytes;
        public ulong UsedMemoryBytes;
        public ulong AvailableMemoryBytes;
        public ulong TotalSwapBytes;
        public ulong UsedSwapBytes;
        public ulong ElapsedMs;

        public bool IsSuccess => Status == PcaiStatus.Success;

        public double MemoryUsagePercent => TotalMemoryBytes > 0
            ? (double)UsedMemoryBytes / TotalMemoryBytes * 100.0
            : 0.0;

        public double SwapUsagePercent => TotalSwapBytes > 0
            ? (double)UsedSwapBytes / TotalSwapBytes * 100.0
            : 0.0;
    }

    /// <summary>
    /// P/Invoke declarations for pcai_core_lib.dll (consolidated from performance module).
    /// Provides disk usage analysis, process monitoring, and memory statistics.
    /// </summary>
    public static class PerformanceModule
    {
        private static readonly Lazy<bool> _isAvailable = new(() =>
        {
            try { return NativeCore.pcai_core_test() == 0x50434149; }
            catch { return false; }
        });

        public static bool IsAvailable => _isAvailable.Value;

        // ====================================================================
        // Disk Usage Functions
        // ====================================================================


        /// <summary>
        /// Get disk usage statistics for a directory.
        /// </summary>
        /// <param name="rootPath">Path to analyze.</param>
        /// <param name="topN">Number of top subdirectories to include in breakdown.</param>
        /// <returns>Disk usage statistics.</returns>
        public static DiskUsageStats GetDiskUsage(string rootPath, uint topN = 10)
        {
            return NativeCore.pcai_get_disk_usage(rootPath, topN);
        }

        /// <summary>
        /// Get disk usage as JSON with detailed breakdown.
        /// </summary>
        /// <param name="rootPath">Path to analyze.</param>
        /// <param name="topN">Number of top subdirectories to include.</param>
        /// <returns>JSON string with usage details, or null on error.</returns>
        public static string? GetDiskUsageJson(string rootPath, uint topN = 10)
        {
            var buffer = NativeCore.pcai_get_disk_usage_json(rootPath, topN);
            try
            {
                return buffer.ToManagedString();
            }
            finally
            {
                NativeCore.pcai_free_string_buffer(ref buffer);
            }
        }

        // ====================================================================
        // Process Functions
        // ====================================================================


        /// <summary>
        /// Get system-wide process statistics.
        /// </summary>
        /// <returns>Process statistics including counts and CPU/memory usage.</returns>
        public static ProcessStats GetProcessStats()
        {
            return NativeCore.pcai_get_process_stats();
        }

        /// <summary>
        /// Get top processes as JSON, sorted by memory or CPU.
        /// </summary>
        /// <param name="topN">Number of top processes to return.</param>
        /// <param name="sortBy">"memory" (default) or "cpu".</param>
        /// <returns>JSON string with process list, or null on error.</returns>
        public static string? GetTopProcessesJson(uint topN = 20, string sortBy = "memory")
        {
            var buffer = NativeCore.pcai_get_top_processes_json(topN, sortBy);
            try
            {
                return buffer.ToManagedString();
            }
            finally
            {
                NativeCore.pcai_free_string_buffer(ref buffer);
            }
        }

        // ====================================================================
        // Memory Functions
        // ====================================================================


        /// <summary>
        /// Get system memory statistics.
        /// </summary>
        /// <returns>Memory statistics including RAM and swap usage.</returns>
        public static MemoryStats GetMemoryStats()
        {
            return NativeCore.pcai_get_memory_stats();
        }

        /// <summary>
        /// Get memory statistics as JSON with detailed breakdown.
        /// </summary>
        /// <returns>JSON string with memory details, or null on error.</returns>
        public static string? GetMemoryStatsJson()
        {
            var buffer = NativeCore.pcai_get_memory_stats_json();
            try
            {
                return buffer.ToManagedString();
            }
            finally
            {
                NativeCore.pcai_free_string_buffer(ref buffer);
            }
        }

        /// <summary>
        /// Queries structured hardware metrics natively.
        /// </summary>
        public static PcaiMetrics? GetResourceMetrics()
        {
            // Placeholder - returns null until structured struct is ready
            return null;
        }

        /// <summary>
        /// Queries hardware metrics JSON natively.
        /// </summary>
        public static string? QueryHardwareMetrics()
        {
            var buffer = NativeCore.pcai_query_hardware_metrics();
            try
            {
                return buffer.ToManagedString();
            }
            finally
            {
                NativeCore.pcai_free_string_buffer(ref buffer);
            }
        }

        /// <summary>
        /// Gets network throughput and stats using IPHelper.
        /// </summary>
        public static string? GetNetworkThroughput()
        {
            if (!IsAvailable) return null;
            var ptr = NativeCore.pcai_get_network_throughput_json();
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
        /// Gets detailed process history using Psapi.
        /// </summary>
        public static string? GetProcessHistory()
        {
            if (!IsAvailable) return null;
            var ptr = NativeCore.pcai_get_process_history_json();
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
        /// Checks if system resources are within safety limits (e.g. 80% load).
        /// </summary>
        public static bool CheckResourceSafety(float gpuLimit = 0.8f)
        {
            return NativeCore.pcai_check_resource_safety(gpuLimit) != 0;
        }

        // ====================================================================
        // Utility Functions
        // ====================================================================


        /// <summary>
        /// Get the performance module version.
        /// </summary>
        /// <returns>Version encoded as 0xMMmmpp (major.minor.patch).</returns>
        public static uint GetVersion()
        {
            return 0x010000;
        }

        /// <summary>
        /// Test if the performance DLL is loaded correctly.
        /// </summary>
        /// <returns>True if the magic number matches.</returns>
        public static bool Test()
        {
            const uint expectedMagic = 0x50434149; // "PCAI"
            return NativeCore.pcai_core_test() == expectedMagic;
        }

        /// <summary>
        /// Format bytes as human-readable string.
        /// </summary>
        public static string FormatBytes(ulong bytes)
        {
            const ulong KB = 1024;
            const ulong MB = KB * 1024;
            const ulong GB = MB * 1024;
            const ulong TB = GB * 1024;

            return bytes switch
            {
                >= TB => $"{bytes / (double)TB:F2} TB",
                >= GB => $"{bytes / (double)GB:F2} GB",
                >= MB => $"{bytes / (double)MB:F2} MB",
                >= KB => $"{bytes / (double)KB:F2} KB",
                _ => $"{bytes} B"
            };
        }
    }
}
