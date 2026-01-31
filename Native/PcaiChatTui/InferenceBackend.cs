// InferenceBackend.cs - Backend selection for TUI
using System.Net.Http.Json;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading.Channels;

namespace PcaiChatTui;

public enum BackendType
{
    Auto,
    Http,       // pcai-inference via HTTP (OpenAI-compatible)
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
            BackendType.Http => new HttpBackend(httpEndpoint ?? "http://127.0.0.1:8080"),
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

        return new HttpBackend(httpEndpoint ?? "http://127.0.0.1:8080");
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

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void TokenCallback(IntPtr token, IntPtr userData);

    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int pcai_generate_streaming(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string prompt,
        uint maxTokens,
        float temperature,
        TokenCallback callback,
        IntPtr userData);

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
        var channel = Channel.CreateUnbounded<string>();
        TokenCallback? callback = null;
        callback = (tokenPtr, _) =>
        {
            if (tokenPtr == IntPtr.Zero) return;
            var token = Marshal.PtrToStringUTF8(tokenPtr);
            if (!string.IsNullOrEmpty(token))
            {
                channel.Writer.TryWrite(token);
            }
        };

        _ = Task.Run(() =>
        {
            var result = pcai_generate_streaming(prompt, (uint)maxTokens, temperature, callback, IntPtr.Zero);
            if (result != 0)
            {
                var errorPtr = pcai_last_error();
                var error = errorPtr != IntPtr.Zero ? Marshal.PtrToStringUTF8(errorPtr) : "Unknown error";
                channel.Writer.TryComplete(new InvalidOperationException($"Streaming failed: {error}"));
                return;
            }
            channel.Writer.TryComplete();
        });

        await foreach (var token in channel.Reader.ReadAllAsync())
        {
            yield return token;
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

// HTTP backend (pcai-inference OpenAI-compatible)
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
                var response = _client.GetAsync($"{_endpoint}/v1/models").Result;
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
            model = "pcai-inference",
            prompt = prompt,
            stream = false,
            temperature = temperature,
            max_tokens = maxTokens
        };

        var content = new StringContent(JsonSerializer.Serialize(request), System.Text.Encoding.UTF8, "application/json");
        var response = await _client.PostAsync($"{_endpoint}/v1/completions", content);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);
        var choices = doc.RootElement.GetProperty("choices");
        if (choices.GetArrayLength() == 0)
        {
            return string.Empty;
        }
        return choices[0].GetProperty("text").GetString() ?? "";
    }

    public async IAsyncEnumerable<string> GenerateStreamingAsync(string prompt, int maxTokens = 2048, float temperature = 0.7f)
    {
        var request = new
        {
            model = "pcai-inference",
            prompt = prompt,
            stream = true,
            temperature = temperature,
            max_tokens = maxTokens
        };

        var content = new StringContent(JsonSerializer.Serialize(request), System.Text.Encoding.UTF8, "application/json");
        var response = await _client.PostAsync($"{_endpoint}/v1/completions", content);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync();
        using var reader = new StreamReader(stream);

        while (!reader.EndOfStream)
        {
            var line = await reader.ReadLineAsync();
            if (string.IsNullOrEmpty(line)) continue;

            if (!line.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var payload = line.Substring(5).Trim();
            if (string.Equals(payload, "[DONE]", StringComparison.OrdinalIgnoreCase))
            {
                yield break;
            }

            using var doc = JsonDocument.Parse(payload);
            if (doc.RootElement.TryGetProperty("choices", out var choices) && choices.GetArrayLength() > 0)
            {
                var choice = choices[0];
                if (choice.TryGetProperty("text", out var token))
                {
                    yield return token.GetString() ?? "";
                }
            }
        }
    }

    public ValueTask DisposeAsync()
    {
        _client.Dispose();
        return ValueTask.CompletedTask;
    }
}
