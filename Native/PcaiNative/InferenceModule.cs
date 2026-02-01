using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
using System.IO;

namespace PcaiNative
{
    /// <summary>
    /// P/Invoke interop with pcai_inference.dll
    /// </summary>
    public static class InferenceModule
    {
        private const string DllName = "pcai_inference";

        /// <summary>
        /// Static constructor to register native library resolver
        /// </summary>
        static InferenceModule()
        {
            NativeLibrary.SetDllImportResolver(typeof(InferenceModule).Assembly, ResolveDll);
        }

        /// <summary>
        /// Custom DLL resolver for pcai_inference.dll
        /// </summary>
        private static IntPtr ResolveDll(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
        {
            if (libraryName != DllName)
                return IntPtr.Zero;

            // Try default resolution first
            if (NativeLibrary.TryLoad(libraryName, assembly, searchPath, out IntPtr handle))
                return handle;

            // Search paths in priority order
            var searchPaths = new List<string>();

            // 1. Runtime native folder (deployed by build script)
            var assemblyDir = Path.GetDirectoryName(assembly.Location);
            if (!string.IsNullOrEmpty(assemblyDir))
            {
                searchPaths.Add(Path.Combine(assemblyDir, "runtimes", "win-x64", "native", "pcai_inference.dll"));
                searchPaths.Add(Path.Combine(assemblyDir, "pcai_inference.dll"));
            }

            // 2. PC_AI bin directory
            var moduleDir = Environment.GetEnvironmentVariable("PSScriptRoot");
            if (!string.IsNullOrEmpty(moduleDir))
            {
                var projectBin = Path.GetFullPath(Path.Combine(moduleDir, "..", "..", "bin", "pcai_inference.dll"));
                searchPaths.Add(projectBin);
            }

            // 3. Common project locations
            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            searchPaths.Add(Path.Combine(userProfile, "PC_AI", "bin", "pcai_inference.dll"));

            // 4. CARGO_TARGET_DIR if set
            var cargoTarget = Environment.GetEnvironmentVariable("CARGO_TARGET_DIR");
            if (!string.IsNullOrEmpty(cargoTarget))
            {
                searchPaths.Add(Path.Combine(cargoTarget, "release", "pcai_inference.dll"));
            }

            foreach (var path in searchPaths)
            {
                if (File.Exists(path) && NativeLibrary.TryLoad(path, out handle))
                    return handle;
            }

            return IntPtr.Zero;
        }

        #region Native Imports

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int pcai_init([MarshalAs(UnmanagedType.LPUTF8Str)] string backendName);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int pcai_load_model([MarshalAs(UnmanagedType.LPUTF8Str)] string modelPath, int gpuLayers);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern IntPtr pcai_generate([MarshalAs(UnmanagedType.LPUTF8Str)] string prompt, uint maxTokens, float temperature);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int pcai_generate_streaming([MarshalAs(UnmanagedType.LPUTF8Str)] string prompt, uint maxTokens, float temperature, TokenCallback callback, IntPtr userData);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void pcai_shutdown();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr pcai_last_error();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int pcai_last_error_code();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void pcai_free_string(IntPtr ptr);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int pcai_is_initialized();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int pcai_is_model_loaded();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr pcai_get_backend_name();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        public delegate void TokenCallback(IntPtr token, IntPtr userData);

        #endregion

        #region High-level Wrappers

        public static bool IsAvailable => pcai_is_initialized() != 0 || IsDllAvailable();

        private static bool IsDllAvailable()
        {
            try { return pcai_last_error_code() >= 0; }
            catch { return false; }
        }

        public static string? Generate(string prompt, uint maxTokens = 512, float temperature = 0.7f)
        {
            var ptr = pcai_generate(prompt, maxTokens, temperature);
            if (ptr == IntPtr.Zero) return null;
            try { return Marshal.PtrToStringUTF8(ptr); }
            finally { pcai_free_string(ptr); }
        }

        public static string? GetLastError()
        {
            var ptr = pcai_last_error();
            return ptr == IntPtr.Zero ? null : Marshal.PtrToStringUTF8(ptr);
        }

        #endregion
    }
}
