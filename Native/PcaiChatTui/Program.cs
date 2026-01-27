using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using PcaiNative;

namespace PcaiChatTui;

public static class Program
{
    private const string DefaultBaseUrl = "http://localhost:11434";
    private const string DefaultModel = "qwen2.5-coder:7b";
    private const int DefaultTimeoutSec = 120;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    public static async Task<int> Main(string[] args)
    {
        var options = CliOptions.Parse(args);
        var config = LlmConfig.Load(options.ConfigPath);

        var baseUrl = NormalizeBaseUrl(options.BaseUrl ?? config.BaseUrl ?? DefaultBaseUrl);
        var model = options.Model ?? config.DefaultModel ?? DefaultModel;
        var timeoutSec = options.TimeoutSec ?? config.TimeoutSec ?? DefaultTimeoutSec;

        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(timeoutSec) };

        var systemPrompt = options.SystemPrompt;
        if (string.IsNullOrWhiteSpace(systemPrompt) && !string.IsNullOrWhiteSpace(options.SystemFile))
        {
            if (File.Exists(options.SystemFile))
            {
                systemPrompt = File.ReadAllText(options.SystemFile);
            }
        }

        if (options.HealthOnly)
        {
            var health = await GetHealthAsync(http, baseUrl);
            PrintHealth(health, options.JsonOutput);
            return health.Ok ? 0 : 1;
        }

        if (options.ModelsOnly)
        {
            var models = await GetModelsAsync(http, baseUrl);
            if (options.JsonOutput)
            {
                Console.WriteLine(JsonSerializer.Serialize(models, JsonOptions));
            }
            else
            {
                Console.WriteLine("Available models:");
                foreach (var name in models)
                {
                    Console.WriteLine($"- {name}");
                }
            }
            return 0;
        }

        PrintBanner(baseUrl, model);
        await RunInteractiveAsync(http, baseUrl, model, systemPrompt);
        return 0;
    }

    private static void PrintBanner(string baseUrl, string model)
    {
        Console.WriteLine("PC_AI Chat TUI");
        Console.WriteLine($"Endpoint: {baseUrl}");
        Console.WriteLine($"Model: {model}");
        Console.WriteLine("Commands: /health, /models, /reset, /exit");
        Console.WriteLine();
    }

    private static async Task RunInteractiveAsync(HttpClient http, string baseUrl, string model, string? systemPrompt)
    {
        var history = new List<ChatMessage>();
        if (!string.IsNullOrWhiteSpace(systemPrompt))
        {
            history.Add(new ChatMessage("system", systemPrompt));
            Console.WriteLine("System prompt loaded. Use /reset to clear context.");
        }

        while (true)
        {
            Console.Write("you> ");
            var input = Console.ReadLine();
            if (string.IsNullOrWhiteSpace(input))
            {
                continue;
            }

            if (input.StartsWith("/", StringComparison.OrdinalIgnoreCase))
            {
                var command = input.Trim().ToLowerInvariant();
                switch (command)
                {
                    case "/exit":
                    case "/quit":
                        return;
                    case "/reset":
                        history.Clear();
                        Console.WriteLine("Context cleared.");
                        continue;
                    case "/health":
                        var health = await GetHealthAsync(http, baseUrl);
                        PrintHealth(health, jsonOutput: false);
                        continue;
                    case "/models":
                        var models = await GetModelsAsync(http, baseUrl);
                        Console.WriteLine("Available models:");
                        foreach (var name in models)
                        {
                            Console.WriteLine($"- {name}");
                        }
                        continue;
                    default:
                        Console.WriteLine("Unknown command.");
                        continue;
                }
            }

            history.Add(new ChatMessage("user", input));

            try
            {
                var request = new OllamaChatRequest
                {
                    Model = model,
                    Stream = false,
                    Messages = history
                };

                var response = await http.PostAsJsonAsync($"{baseUrl}/api/chat", request, JsonOptions);
                response.EnsureSuccessStatusCode();

                var payload = await response.Content.ReadFromJsonAsync<OllamaChatResponse>(JsonOptions);
                var content = payload?.Message?.Content ?? string.Empty;

                history.Add(new ChatMessage("assistant", content));
                Console.WriteLine($"assistant> {content}\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"error> {ex.Message}");
            }
        }
    }

    private static async Task<HealthResult> GetHealthAsync(HttpClient http, string baseUrl)
    {
        var result = new HealthResult
        {
            Endpoint = baseUrl,
            Native = PcaiCore.GetDiagnostics()
        };

        try
        {
            var response = await http.GetFromJsonAsync<OllamaVersion>($"{baseUrl}/api/version", JsonOptions);
            result.Ok = response != null;
            result.Version = response?.Version ?? "unknown";
        }
        catch (Exception ex)
        {
            result.Ok = false;
            result.Error = ex.Message;
        }

        return result;
    }

    private static async Task<IReadOnlyList<string>> GetModelsAsync(HttpClient http, string baseUrl)
    {
        var tags = await http.GetFromJsonAsync<OllamaTags>($"{baseUrl}/api/tags", JsonOptions);
        if (tags?.Models == null)
        {
            return Array.Empty<string>();
        }

        return tags.Models.Select(m => m.Name).ToArray();
    }

    private static void PrintHealth(HealthResult health, bool jsonOutput)
    {
        if (jsonOutput)
        {
            Console.WriteLine(JsonSerializer.Serialize(health, JsonOptions));
            return;
        }

        Console.WriteLine("LLM Health");
        Console.WriteLine($"  Endpoint: {health.Endpoint}");
        Console.WriteLine($"  Status: {(health.Ok ? "OK" : "ERROR")}");
        if (!string.IsNullOrWhiteSpace(health.Version))
        {
            Console.WriteLine($"  Version: {health.Version}");
        }
        if (!string.IsNullOrWhiteSpace(health.Error))
        {
            Console.WriteLine($"  Error: {health.Error}");
        }

        Console.WriteLine("Native Diagnostics");
        Console.WriteLine($"  Available: {health.Native.IsAvailable}");
        Console.WriteLine($"  Version: {health.Native.Version}");
        Console.WriteLine($"  CPU: {health.Native.CpuCount}");
    }

    private static string NormalizeBaseUrl(string url)
    {
        return url.TrimEnd('/');
    }
}

public sealed class CliOptions
{
    public string? BaseUrl { get; init; }
    public string? Model { get; init; }
    public string? ConfigPath { get; init; }
    public int? TimeoutSec { get; init; }
    public bool HealthOnly { get; init; }
    public bool ModelsOnly { get; init; }
    public bool JsonOutput { get; init; }
    public string? SystemPrompt { get; init; }
    public string? SystemFile { get; init; }

    public static CliOptions Parse(string[] args)
    {
        string? baseUrl = null;
        string? model = null;
        string? configPath = null;
        int? timeoutSec = null;
        bool health = false;
        bool models = false;
        bool json = false;
        string? systemPrompt = null;
        string? systemFile = null;

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            switch (arg)
            {
                case "--base-url":
                case "-u":
                    baseUrl = NextValue(args, ref i);
                    break;
                case "--model":
                case "-m":
                    model = NextValue(args, ref i);
                    break;
                case "--config":
                case "-c":
                    configPath = NextValue(args, ref i);
                    break;
                case "--timeout":
                    if (int.TryParse(NextValue(args, ref i), out var parsed))
                    {
                        timeoutSec = parsed;
                    }
                    break;
                case "--health":
                    health = true;
                    break;
                case "--models":
                    models = true;
                    break;
                case "--json":
                    json = true;
                    break;
                case "--system":
                    systemPrompt = NextValue(args, ref i);
                    break;
                case "--system-file":
                    systemFile = NextValue(args, ref i);
                    break;
            }
        }

        return new CliOptions
        {
            BaseUrl = baseUrl,
            Model = model,
            ConfigPath = configPath,
            TimeoutSec = timeoutSec,
            HealthOnly = health,
            ModelsOnly = models,
            JsonOutput = json,
            SystemPrompt = systemPrompt,
            SystemFile = systemFile
        };
    }

    private static string NextValue(string[] args, ref int index)
    {
        if (index + 1 >= args.Length)
        {
            return string.Empty;
        }

        index++;
        return args[index];
    }
}

public sealed class LlmConfig
{
    public string? BaseUrl { get; init; }
    public string? DefaultModel { get; init; }
    public int? TimeoutSec { get; init; }

    public static LlmConfig Load(string? configPath)
    {
        var path = configPath ?? "C:\\Users\\david\\PC_AI\\Config\\llm-config.json";
        if (!File.Exists(path))
        {
            return new LlmConfig();
        }

        try
        {
            using var stream = File.OpenRead(path);
            using var doc = JsonDocument.Parse(stream);
            if (!doc.RootElement.TryGetProperty("providers", out var providers))
            {
                return new LlmConfig();
            }

            if (!providers.TryGetProperty("ollama", out var ollama))
            {
                return new LlmConfig();
            }

            var baseUrl = ollama.TryGetProperty("baseUrl", out var baseUrlElement)
                ? baseUrlElement.GetString()
                : null;
            var model = ollama.TryGetProperty("defaultModel", out var modelElement)
                ? modelElement.GetString()
                : null;
            var timeout = ollama.TryGetProperty("timeout", out var timeoutElement)
                ? timeoutElement.GetInt32() / 1000
                : (int?)null;

            return new LlmConfig
            {
                BaseUrl = baseUrl,
                DefaultModel = model,
                TimeoutSec = timeout
            };
        }
        catch
        {
            return new LlmConfig();
        }
    }
}

public sealed class HealthResult
{
    [JsonPropertyName("ok")]
    public bool Ok { get; set; }

    [JsonPropertyName("endpoint")]
    public string Endpoint { get; set; } = string.Empty;

    [JsonPropertyName("version")]
    public string? Version { get; set; }

    [JsonPropertyName("error")]
    public string? Error { get; set; }

    [JsonPropertyName("native")]
    public NativeDiagnostics Native { get; set; } = new();
}

public sealed class OllamaVersion
{
    [JsonPropertyName("version")]
    public string Version { get; set; } = string.Empty;
}

public sealed class OllamaTags
{
    [JsonPropertyName("models")]
    public List<OllamaModel>? Models { get; set; }
}

public sealed class OllamaModel
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;
}

public sealed class OllamaChatRequest
{
    [JsonPropertyName("model")]
    public string Model { get; set; } = string.Empty;

    [JsonPropertyName("stream")]
    public bool Stream { get; set; }

    [JsonPropertyName("messages")]
    public List<ChatMessage> Messages { get; set; } = new();
}

public sealed class OllamaChatResponse
{
    [JsonPropertyName("message")]
    public ChatMessage? Message { get; set; }
}

public sealed class ChatMessage
{
    public ChatMessage() { }

    public ChatMessage(string role, string content)
    {
        Role = role;
        Content = content;
    }

    [JsonPropertyName("role")]
    public string Role { get; set; } = string.Empty;

    [JsonPropertyName("content")]
    public string Content { get; set; } = string.Empty;
}

