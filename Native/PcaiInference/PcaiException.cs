namespace PcaiInference;

/// <summary>
/// Error codes returned by pcai-inference FFI
/// </summary>
public enum PcaiErrorCode
{
    /// <summary>Operation completed successfully</summary>
    Success = 0,

    /// <summary>Backend not initialized - call Initialize first</summary>
    NotInitialized = -1,

    /// <summary>Model not loaded - call LoadModel first</summary>
    ModelNotLoaded = -2,

    /// <summary>Invalid input - null pointer, invalid UTF-8, or out of range</summary>
    InvalidInput = -3,

    /// <summary>Backend operation failed - check error message for details</summary>
    BackendError = -4,

    /// <summary>I/O error - file not found or permission denied</summary>
    IoError = -5,

    /// <summary>Unknown or unclassified error</summary>
    Unknown = -99
}

/// <summary>
/// Exception thrown by PcaiInference operations
/// </summary>
public class PcaiException : Exception
{
    /// <summary>
    /// The error code from the native library
    /// </summary>
    public PcaiErrorCode ErrorCode { get; }

    /// <summary>
    /// Additional context about the error
    /// </summary>
    public string? NativeError { get; }

    /// <summary>
    /// Create a new PcaiException with an error code
    /// </summary>
    /// <param name="errorCode">The error code from native library</param>
    /// <param name="message">Optional custom message</param>
    /// <param name="nativeError">Optional native error details</param>
    public PcaiException(PcaiErrorCode errorCode, string? message = null, string? nativeError = null)
        : base(message ?? GetDefaultMessage(errorCode, nativeError))
    {
        ErrorCode = errorCode;
        NativeError = nativeError;
    }

    /// <summary>
    /// Create a new PcaiException with an inner exception
    /// </summary>
    /// <param name="errorCode">The error code from native library</param>
    /// <param name="message">Error message</param>
    /// <param name="innerException">The inner exception</param>
    public PcaiException(PcaiErrorCode errorCode, string message, Exception innerException)
        : base(message, innerException)
    {
        ErrorCode = errorCode;
    }

    private static string GetDefaultMessage(PcaiErrorCode code, string? nativeError)
    {
        string baseMessage = code switch
        {
            PcaiErrorCode.Success => "Operation completed successfully",
            PcaiErrorCode.NotInitialized => "Backend not initialized. Call Initialize() first.",
            PcaiErrorCode.ModelNotLoaded => "No model loaded. Call LoadModelAsync() first.",
            PcaiErrorCode.InvalidInput => "Invalid input provided to native function.",
            PcaiErrorCode.BackendError => "Backend inference operation failed.",
            PcaiErrorCode.IoError => "I/O error - file not found or permission denied.",
            PcaiErrorCode.Unknown => "Unknown error occurred in native library.",
            _ => $"Native error code: {(int)code}"
        };

        return string.IsNullOrEmpty(nativeError)
            ? baseMessage
            : $"{baseMessage} Details: {nativeError}";
    }

    /// <summary>
    /// Create exception from native error code with automatic message lookup
    /// </summary>
    public static PcaiException FromErrorCode(int errorCode, string? operation = null)
    {
        var code = (PcaiErrorCode)errorCode;
        var nativeError = PcaiInterop.GetLastError();

        string message = string.IsNullOrEmpty(operation)
            ? GetDefaultMessage(code, nativeError)
            : $"{operation} failed: {GetDefaultMessage(code, nativeError)}";

        return new PcaiException(code, message, nativeError);
    }

    /// <summary>
    /// Throw if error code indicates failure
    /// </summary>
    public static void ThrowIfError(int errorCode, string? operation = null)
    {
        if (errorCode != 0)
        {
            throw FromErrorCode(errorCode, operation);
        }
    }
}

/// <summary>
/// Exception thrown when the native DLL is not available
/// </summary>
public class PcaiDllNotFoundException : PcaiException
{
    /// <summary>
    /// Create a new PcaiDllNotFoundException with default message
    /// </summary>
    public PcaiDllNotFoundException()
        : base(PcaiErrorCode.NotInitialized,
               "pcai_inference.dll not found. Build with: cd Deploy\\pcai-inference && .\\build.ps1")
    {
    }

    /// <summary>
    /// Create a new PcaiDllNotFoundException with specific path
    /// </summary>
    /// <param name="dllPath">The path where DLL was expected</param>
    public PcaiDllNotFoundException(string dllPath)
        : base(PcaiErrorCode.NotInitialized,
               $"pcai_inference.dll not found at {dllPath}. Build with: cd Deploy\\pcai-inference && .\\build.ps1")
    {
    }
}
