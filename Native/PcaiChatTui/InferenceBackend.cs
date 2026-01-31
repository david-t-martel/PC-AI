// InferenceBackend.cs - Backend selection for TUI
using System.Net.Http.Json;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace PcaiChatTui;

public enum BackendType
{
    Auto,
    Http,       // Ollama/vLLM/LM Studio via HTTP
    LlamaCpp,   // Native llama.cpp via FFI
    MistralRs   // Native mistral.rs via FFI
}

public interface IInferenceBackend : IAsyncDisposable
{
    string Name { get; }
    bool IsAvailable { get; }
    Task<bool> LoadModelAsync(string modelPath, int gpuLayers = -1);
    Task<string> GenerateAsync(string prompt, int maxTokens = 2048, float temperature = 0.7f);
    IAsyncEnumerable<string> GenerateStreamingAsync(string prompt, int maxTokens = 2048, float temperature = 0.7f);
}

public static class BackendFactory
{
    public static IInferenceBackend Create(BackendType type, string? httpEndpoint = null)
    {
        return type switch
        {
            BackendType.Http => new HttpBackend(httpEndpoint ?? "http://localhost:11434"),
            BackendType.LlamaCpp => new NativeBackend("llamacpp"),
            BackendType.MistralRs => new NativeBackend("mistralrs"),
            BackendType.Auto => ResolveAuto(httpEndpoint),
            _ => throw new ArgumentException($"Unknown backend type: {type}")
        };
    }

    private static IInferenceBackend ResolveAuto(string? httpEndpoint)
    {
        // Try native first, fall back to HTTP
        var native = new NativeBackend("mistralrs");
        if (native.IsAvailable)
            return native;

        native = new NativeBackend("llamacpp");
        if (native.IsAvailable)
            return native;

        return new HttpBackend(httpEndpoint ?? "http://localhost:11434");
    }
}

// Native FFI backend
public class NativeBackend : IInferenceBackend
{
    private readonly string _backendName;
    private bool _initialized;
    private bool _disposed;

    // P/Invoke declarations
    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int pcai_init([MarshalAs(UnmanagedType.LPUTF8Str)] string? backendName);

    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int pcai_load_model([MarshalAs(UnmanagedType.LPUTF8Str)] string modelPath, int gpuLayers);

    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr pcai_generate([MarshalAs(UnmanagedType.LPUTF8Str)] string prompt, uint maxTokens, float temperature);

    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void pcai_free_string(IntPtr str);

    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void pcai_shutdown();

    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr pcai_last_error();

    public NativeBackend(string backendName)
    {
        _backendName = backendName;
    }

    public string Name => $"Native ({_backendName})";

    public bool IsAvailable
    {
        get
        {
            try
            {
                // Check if DLL exists and can initialize
                var result = pcai_init(_backendName);
                if (result == 0)
                {
                    _initialized = true;
                    return true;
                }
                return false;
            }
            catch (DllNotFoundException)
            {
                return false;
            }
        }
    }

    public Task<bool> LoadModelAsync(string modelPath, int gpuLayers = -1)
    {
        if (!_initialized)
        {
            var initResult = pcai_init(_backendName);
            if (initResult != 0)
                return Task.FromResult(false);
            _initialized = true;
        }

        var result = pcai_load_model(modelPath, gpuLayers);
        return Task.FromResult(result == 0);
    }

    public Task<string> GenerateAsync(string prompt, int maxTokens = 2048, float temperature = 0.7f)
    {
        var resultPtr = pcai_generate(prompt, (uint)maxTokens, temperature);
        if (resultPtr == IntPtr.Zero)
        {
            var errorPtr = pcai_last_error();
            var error = errorPtr != IntPtr.Zero ? Marshal.PtrToStringUTF8(errorPtr) : "Unknown error";
            throw new InvalidOperationException($"Generation failed: {error}");
        }

        try
        {
            return Task.FromResult(Marshal.PtrToStringUTF8(resultPtr) ?? "");
        }
        finally
        {
            pcai_free_string(resultPtr);
        }
    }

    public async IAsyncEnumerable<string> GenerateStreamingAsync(string prompt, int maxTokens = 2048, float temperature = 0.7f)
    {
        // For now, non-streaming fallback
        var result = await GenerateAsync(prompt, maxTokens, temperature);
        foreach (var word in result.Split(' '))
        {
            yield return word + " ";
            await Task.Delay(10); // Simulate streaming
        }
    }

    public ValueTask DisposeAsync()
    {
        if (!_disposed && _initialized)
        {
            pcai_shutdown();
            _disposed = true;
        }
        return ValueTask.CompletedTask;
    }
}

// HTTP backend (Ollama/vLLM/LM Studio)
public class HttpBackend : IInferenceBackend
{
    private readonly HttpClient _client;
    private readonly string _endpoint;

    public HttpBackend(string endpoint)
    {
        _endpoint = endpoint.TrimEnd('/');
        _client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
    }

    public string Name => $"HTTP ({_endpoint})";

    public bool IsAvailable
    {
        get
        {
            try
            {
                var response = _client.GetAsync($"{_endpoint}/api/tags").Result;
                return response.IsSuccessStatusCode;
            }
            catch
            {
                return false;
            }
        }
    }

    public Task<bool> LoadModelAsync(string modelPath, int gpuLayers = -1)
    {
        // HTTP backends auto-load models
        return Task.FromResult(true);
    }

    public async Task<string> GenerateAsync(string prompt, int maxTokens = 2048, float temperature = 0.7f)
    {
        var request = new
        {
            model = "default",
            prompt = prompt,
            stream = false,
            options = new { temperature, num_predict = maxTokens }
        };

        var content = new StringContent(JsonSerializer.Serialize(request), System.Text.Encoding.UTF8, "application/json");
        var response = await _client.PostAsync($"{_endpoint}/api/generate", content);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("response").GetString() ?? "";
    }

    public async IAsyncEnumerable<string> GenerateStreamingAsync(string prompt, int maxTokens = 2048, float temperature = 0.7f)
    {
        var request = new
        {
            model = "default",
            prompt = prompt,
            stream = true,
            options = new { temperature, num_predict = maxTokens }
        };

        var content = new StringContent(JsonSerializer.Serialize(request), System.Text.Encoding.UTF8, "application/json");
        var response = await _client.PostAsync($"{_endpoint}/api/generate", content);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync();
        using var reader = new StreamReader(stream);

        while (!reader.EndOfStream)
        {
            var line = await reader.ReadLineAsync();
            if (string.IsNullOrEmpty(line)) continue;

            using var doc = JsonDocument.Parse(line);
            if (doc.RootElement.TryGetProperty("response", out var token))
            {
                yield return token.GetString() ?? "";
            }
        }
    }

    public ValueTask DisposeAsync()
    {
        _client.Dispose();
        return ValueTask.CompletedTask;
    }
}
