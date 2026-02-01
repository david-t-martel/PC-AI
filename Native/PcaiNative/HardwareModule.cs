using System;
using System.Runtime.InteropServices;

namespace PcaiNative
{
    /// <summary>
    /// Specialized module for hardware-related native functions.
    /// Provides PnP interrogation, disk health, and event log sampling.
    /// </summary>
    public static class HardwareModule
    {
        /// <summary>
        /// Gets whether the native hardware library functions are available.
        /// </summary>
        public static bool IsAvailable => SystemModule.IsAvailable;

        /// <summary>
        /// Enumerates PnP devices based on an optional class filter.
        /// </summary>
        /// <param name="classFilter">Device class to filter for (e.g. "USB", "DiskDrive") or null.</param>
        /// <returns>JSON string containing list of PnpDeviceDetail objects.</returns>
        public static string? GetPnpDevicesJson(string? classFilter = null)
        {
            if (!IsAvailable) return null;
            var ptr = NativeCore.pcai_get_pnp_devices_json(classFilter);
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
        /// Gets detailed information about a PnP problem code.
        /// </summary>
        public static string? GetPnpProblemInfo(uint code)
        {
            if (!IsAvailable) return null;
            var ptr = NativeCore.pcai_get_pnp_problem_info(code);
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
        /// Queries native disk health and SMART status.
        /// </summary>
        public static string? GetDiskHealthJson()
        {
            if (!IsAvailable) return null;
            var ptr = NativeCore.pcai_get_disk_health_json();
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
        /// Samples hardware-related events from the Windows System Event Log.
        /// </summary>
        public static string? SampleHardwareEventsJson(uint days = 3, uint maxEvents = 50)
        {
            if (!IsAvailable) return null;
            var ptr = NativeCore.pcai_sample_hardware_events_json(days, maxEvents);
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
    }
}
