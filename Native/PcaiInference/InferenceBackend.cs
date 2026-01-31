using System.Runtime.InteropServices;
using System.Threading.Channels;

namespace PcaiInference;

/// <summary>
/// Supported inference backend types
/// </summary>
public enum BackendType
{
    /// <summary>llama.cpp backend (GGUF models, CUDA support)</summary>
    LlamaCpp,

    /// <summary>mistral.rs backend (SafeTensors/GGUF, optimized for Mistral models)</summary>
    MistralRs,

    /// <summary>Auto-detect best available backend</summary>
    Auto
}

/// <summary>
/// Request parameters for text generation
/// </summary>
public record GenerateRequest
{
    /// <summary>Input prompt text</summary>
    public required string Prompt { get; init; }

    /// <summary>Maximum tokens to generate (default: 512)</summary>
    public uint MaxTokens { get; init; } = 512;

    /// <summary>Sampling temperature (0.0-2.0, default: 0.7)</summary>
    public float Temperature { get; init; } = 0.7f;

    /// <summary>Stop sequences (not yet supported in FFI)</summary>
    public string[]? StopSequences { get; init; }
}

/// <summary>
/// Response from text generation
/// </summary>
public record GenerateResponse
{
    /// <summary>Generated text</summary>
    public required string Text { get; init; }

    /// <summary>Whether generation completed normally</summary>
    public bool Completed { get; init; } = true;

    /// <summary>Generation duration</summary>
    public TimeSpan Duration { get; init; }
}

/// <summary>
/// High-level interface for inference backends
/// </summary>
public interface IInferenceBackend : IDisposable
{
    /// <summary>The backend type</summary>
    BackendType BackendType { get; }

    /// <summary>Whether a model is loaded</summary>
    bool IsModelLoaded { get; }

    /// <summary>Load a model file</summary>
    Task LoadModelAsync(string modelPath, int gpuLayers = -1, CancellationToken ct = default);

    /// <summary>Generate text from a prompt</summary>
    Task<GenerateResponse> GenerateAsync(GenerateRequest request, CancellationToken ct = default);

    /// <summary>Generate text with streaming output</summary>
    IAsyncEnumerable<string> GenerateStreamingAsync(GenerateRequest request, CancellationToken ct = default);
}

/// <summary>
/// Native inference backend using pcai_inference.dll
/// </summary>
public sealed class NativeInferenceBackend : IInferenceBackend
{
    private readonly BackendType _backendType;
    private bool _initialized;
    private bool _modelLoaded;
    private bool _disposed;

    /// <inheritdoc/>
    public BackendType BackendType => _backendType;

    /// <inheritdoc/>
    public bool IsModelLoaded => _modelLoaded && !_disposed;

    /// <summary>
    /// Create a new native inference backend
    /// </summary>
    /// <param name="backendType">Backend type to use</param>
    public NativeInferenceBackend(BackendType backendType = BackendType.Auto)
    {
        _backendType = backendType;

        if (!PcaiInterop.IsDllAvailable())
        {
            throw new PcaiDllNotFoundException();
        }
    }

    /// <summary>
    /// Initialize the backend
    /// </summary>
    public void Initialize()
    {
        ThrowIfDisposed();

        if (_initialized)
            return;

        string backendName = _backendType switch
        {
            BackendType.LlamaCpp => "llamacpp",
            BackendType.MistralRs => "mistralrs",
            BackendType.Auto => "mistralrs", // Default to mistralrs, fallback to llamacpp
            _ => throw new ArgumentOutOfRangeException(nameof(_backendType))
        };

        int result = PcaiInterop.pcai_init(backendName);

        // If auto and mistralrs failed, try llamacpp
        if (result != 0 && _backendType == BackendType.Auto)
        {
            result = PcaiInterop.pcai_init("llamacpp");
        }

        PcaiException.ThrowIfError(result, "Initialize backend");
        _initialized = true;
    }

    /// <inheritdoc/>
    public Task LoadModelAsync(string modelPath, int gpuLayers = -1, CancellationToken ct = default)
    {
        ThrowIfDisposed();

        if (!_initialized)
            Initialize();

        if (string.IsNullOrEmpty(modelPath))
            throw new ArgumentNullException(nameof(modelPath));

        if (!File.Exists(modelPath))
            throw new FileNotFoundException($"Model file not found: {modelPath}", modelPath);

        return Task.Run(() =>
        {
            ct.ThrowIfCancellationRequested();

            int result = PcaiInterop.pcai_load_model(modelPath, gpuLayers);
            PcaiException.ThrowIfError(result, "Load model");

            _modelLoaded = true;
        }, ct);
    }

    /// <inheritdoc/>
    public Task<GenerateResponse> GenerateAsync(GenerateRequest request, CancellationToken ct = default)
    {
        ThrowIfDisposed();
        ValidateRequest(request);

        return Task.Run(() =>
        {
            ct.ThrowIfCancellationRequested();

            var startTime = DateTime.UtcNow;

            IntPtr resultPtr = PcaiInterop.pcai_generate(
                request.Prompt,
                request.MaxTokens,
                request.Temperature);

            if (resultPtr == IntPtr.Zero)
            {
                throw PcaiException.FromErrorCode(
                    PcaiInterop.pcai_last_error_code(),
                    "Generate text");
            }

            try
            {
                string? text = PcaiInterop.PtrToStringUtf8(resultPtr);
                var duration = DateTime.UtcNow - startTime;

                return new GenerateResponse
                {
                    Text = text ?? string.Empty,
                    Completed = true,
                    Duration = duration
                };
            }
            finally
            {
                PcaiInterop.pcai_free_string(resultPtr);
            }
        }, ct);
    }

    /// <inheritdoc/>
    public async IAsyncEnumerable<string> GenerateStreamingAsync(
        GenerateRequest request,
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken ct = default)
    {
        ThrowIfDisposed();
        ValidateRequest(request);

        var channel = Channel.CreateUnbounded<string>(new UnboundedChannelOptions
        {
            SingleReader = true,
            SingleWriter = true
        });

        Exception? streamingException = null;

        // Start generation in background
        _ = Task.Run(() =>
        {
            try
            {
                GCHandle channelHandle = GCHandle.Alloc(channel.Writer);
                try
                {
                    int result = PcaiInterop.pcai_generate_streaming(
                        request.Prompt,
                        request.MaxTokens,
                        request.Temperature,
                        StreamingCallback,
                        GCHandle.ToIntPtr(channelHandle));

                    if (result != 0)
                    {
                        streamingException = PcaiException.FromErrorCode(result, "Streaming generation");
                    }
                }
                finally
                {
                    channelHandle.Free();
                }
            }
            catch (Exception ex)
            {
                streamingException = ex;
            }
            finally
            {
                channel.Writer.TryComplete(streamingException);
            }
        }, ct);

        // Yield tokens as they arrive
        await foreach (var token in channel.Reader.ReadAllAsync(ct))
        {
            yield return token;
        }

        if (streamingException != null)
        {
            throw streamingException;
        }
    }

    private static void StreamingCallback(IntPtr tokenPtr, IntPtr userData)
    {
        if (tokenPtr == IntPtr.Zero || userData == IntPtr.Zero)
            return;

        try
        {
            var handle = GCHandle.FromIntPtr(userData);
            if (handle.Target is ChannelWriter<string> writer)
            {
                string? token = PcaiInterop.PtrToStringUtf8(tokenPtr);
                if (!string.IsNullOrEmpty(token))
                {
                    writer.TryWrite(token);
                }
            }
        }
        catch
        {
            // Ignore errors in callback to avoid corrupting native state
        }
    }

    private void ValidateRequest(GenerateRequest request)
    {
        if (!_initialized)
            throw new PcaiException(PcaiErrorCode.NotInitialized);

        if (!_modelLoaded)
            throw new PcaiException(PcaiErrorCode.ModelNotLoaded);

        if (string.IsNullOrEmpty(request.Prompt))
            throw new ArgumentNullException(nameof(request.Prompt));

        if (request.Prompt.Length > 100 * 1024) // 100KB limit
            throw new ArgumentException("Prompt exceeds maximum size (100KB)", nameof(request.Prompt));

        if (request.Temperature < 0 || request.Temperature > 2)
            throw new ArgumentOutOfRangeException(nameof(request.Temperature), "Temperature must be 0.0-2.0");
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_disposed)
            return;

        _disposed = true;

        if (_initialized)
        {
            try
            {
                PcaiInterop.pcai_shutdown();
            }
            catch
            {
                // Best effort cleanup
            }
        }

        _initialized = false;
        _modelLoaded = false;
    }
}

/// <summary>
/// Factory for creating inference backends
/// </summary>
public static class InferenceBackendFactory
{
    /// <summary>
    /// Create the best available inference backend
    /// </summary>
    /// <param name="preferredType">Preferred backend type</param>
    /// <returns>Configured inference backend</returns>
    public static IInferenceBackend Create(BackendType preferredType = BackendType.Auto)
    {
        if (!PcaiInterop.IsDllAvailable())
        {
            throw new PcaiDllNotFoundException();
        }

        return new NativeInferenceBackend(preferredType);
    }

    /// <summary>
    /// Try to create an inference backend, returning null if unavailable
    /// </summary>
    public static IInferenceBackend? TryCreate(BackendType preferredType = BackendType.Auto)
    {
        try
        {
            return Create(preferredType);
        }
        catch (PcaiDllNotFoundException)
        {
            return null;
        }
        catch (DllNotFoundException)
        {
            return null;
        }
    }

    /// <summary>
    /// Check if native inference is available
    /// </summary>
    public static bool IsNativeAvailable() => PcaiInterop.IsDllAvailable();
}
