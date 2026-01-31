using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace PcaiInference;

/// <summary>
/// Low-level P/Invoke interop with pcai_inference.dll
/// </summary>
public static class PcaiInterop
{
    private const string DllName = "pcai_inference";

    /// <summary>
    /// Static constructor to register native library resolver
    /// </summary>
    static PcaiInterop()
    {
        NativeLibrary.SetDllImportResolver(typeof(PcaiInterop).Assembly, ResolveDll);
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
        searchPaths.Add(Path.Combine(userProfile, "PC_AI", "bin", "Release", "pcai_inference.dll"));

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

    #region Core Functions

    /// <summary>
    /// Initialize the inference backend
    /// </summary>
    /// <param name="backendName">Backend name: "llamacpp" or "mistralrs"</param>
    /// <returns>Error code (0 = success)</returns>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    public static extern int pcai_init([MarshalAs(UnmanagedType.LPUTF8Str)] string backendName);

    /// <summary>
    /// Load a model file
    /// </summary>
    /// <param name="modelPath">Path to GGUF or SafeTensors model</param>
    /// <param name="gpuLayers">GPU layers to offload (-1 = all, 0 = CPU only)</param>
    /// <returns>Error code (0 = success)</returns>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    public static extern int pcai_load_model(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string modelPath,
        int gpuLayers);

    /// <summary>
    /// Generate text from a prompt (synchronous)
    /// </summary>
    /// <param name="prompt">Input prompt text</param>
    /// <param name="maxTokens">Maximum tokens to generate</param>
    /// <param name="temperature">Sampling temperature (0.0-2.0)</param>
    /// <returns>Pointer to generated text (must free with pcai_free_string)</returns>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    public static extern IntPtr pcai_generate(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string prompt,
        uint maxTokens,
        float temperature);

    /// <summary>
    /// Generate text with streaming callback
    /// </summary>
    /// <param name="prompt">Input prompt text</param>
    /// <param name="maxTokens">Maximum tokens to generate</param>
    /// <param name="temperature">Sampling temperature</param>
    /// <param name="callback">Callback for each token</param>
    /// <param name="userData">User data passed to callback</param>
    /// <returns>Error code (0 = success)</returns>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    public static extern int pcai_generate_streaming(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string prompt,
        uint maxTokens,
        float temperature,
        TokenCallback callback,
        IntPtr userData);

    /// <summary>
    /// Shutdown the inference backend and free resources
    /// </summary>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void pcai_shutdown();

    #endregion

    #region Error Handling

    /// <summary>
    /// Get the last error message (thread-local)
    /// </summary>
    /// <returns>Pointer to error string (do NOT free)</returns>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr pcai_last_error();

    /// <summary>
    /// Get the last error code (thread-local)
    /// </summary>
    /// <returns>Error code from PcaiErrorCode enum</returns>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int pcai_last_error_code();

    #endregion

    #region Memory Management

    /// <summary>
    /// Free a string returned by pcai_generate
    /// </summary>
    /// <param name="ptr">Pointer to string to free</param>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void pcai_free_string(IntPtr ptr);

    #endregion

    #region Status Query

    /// <summary>
    /// Check if the backend is initialized
    /// </summary>
    /// <returns>1 if initialized, 0 otherwise</returns>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int pcai_is_initialized();

    /// <summary>
    /// Check if a model is loaded
    /// </summary>
    /// <returns>1 if model loaded, 0 otherwise</returns>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int pcai_is_model_loaded();

    /// <summary>
    /// Get the current backend name
    /// </summary>
    /// <returns>Pointer to backend name string (do NOT free)</returns>
    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr pcai_get_backend_name();

    #endregion

    #region Delegates

    /// <summary>
    /// Callback for streaming token generation
    /// </summary>
    /// <param name="token">UTF-8 token string</param>
    /// <param name="userData">User-provided context data</param>
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void TokenCallback(IntPtr token, IntPtr userData);

    #endregion

    #region Helper Methods

    /// <summary>
    /// Read a UTF-8 string from an unmanaged pointer
    /// </summary>
    public static string? PtrToStringUtf8(IntPtr ptr)
    {
        if (ptr == IntPtr.Zero)
            return null;

        // Find string length
        int len = 0;
        unsafe
        {
            byte* p = (byte*)ptr;
            while (p[len] != 0) len++;
        }

        if (len == 0)
            return string.Empty;

        byte[] bytes = new byte[len];
        Marshal.Copy(ptr, bytes, 0, len);
        return Encoding.UTF8.GetString(bytes);
    }

    /// <summary>
    /// Get the last error as a managed string
    /// </summary>
    public static string? GetLastError()
    {
        IntPtr ptr = pcai_last_error();
        return PtrToStringUtf8(ptr);
    }

    /// <summary>
    /// Check if the native DLL is available
    /// </summary>
    public static bool IsDllAvailable()
    {
        try
        {
            // Try to call a simple function
            _ = pcai_is_initialized();
            return true;
        }
        catch (DllNotFoundException)
        {
            return false;
        }
        catch (EntryPointNotFoundException)
        {
            return false;
        }
    }

    #endregion
}
