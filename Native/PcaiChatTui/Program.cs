using System.Net.Http.Json;
using System.Text;
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

        var provider = options.Provider ?? config.DefaultProvider ?? "ollama";
        var providerConfig = config.GetProvider(provider);

        var baseUrl = NormalizeBaseUrl(options.BaseUrl ?? providerConfig?.BaseUrl ?? DefaultBaseUrl);
        baseUrl = ResolveHvsockEndpoint(baseUrl, options.HvsockConfigPath ?? config.HvsockConfigPath);
        var model = options.Model ?? providerConfig?.DefaultModel ?? DefaultModel;
        var timeoutSec = options.TimeoutSec ?? providerConfig?.TimeoutSec ?? DefaultTimeoutSec;
        var mode = options.Mode ?? "chat"; // Default to chat mode

        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(timeoutSec) };

        var systemPrompt = options.SystemPrompt;
        if (string.IsNullOrWhiteSpace(systemPrompt) && !string.IsNullOrWhiteSpace(options.SystemFile))
        {
            if (File.Exists(options.SystemFile))
            {
                systemPrompt = File.ReadAllText(options.SystemFile);
            }
        }

        // If no system prompt provided, load default for mode
        if (string.IsNullOrWhiteSpace(systemPrompt))
        {
            systemPrompt = LoadModePrompt(mode);
        }

        if (options.HealthOnly)
        {
            var health = await GetHealthAsync(http, baseUrl, provider);
            PrintHealth(health, options.JsonOutput);
            return health.Ok ? 0 : 1;
        }

        if (options.ModelsOnly)
        {
            var models = await GetModelsAsync(http, baseUrl, provider);
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

        PrintBanner(baseUrl, model, provider, mode);

        if (string.Equals(mode, "single", StringComparison.OrdinalIgnoreCase))
        {
            var prompt = options.Prompt;
            if (string.IsNullOrWhiteSpace(prompt))
            {
                Console.Write("prompt> ");
                prompt = Console.ReadLine();
            }

            if (!string.IsNullOrWhiteSpace(prompt))
            {
                await RunSingleAsync(http, baseUrl, model, provider, systemPrompt, prompt);
            }
            return 0;
        }

        var stream = string.Equals(mode, "stream", StringComparison.OrdinalIgnoreCase);
        var react = string.Equals(mode, "react", StringComparison.OrdinalIgnoreCase) || mode == "diagnose";
        var toolsPath = options.ToolsPath ?? config.ToolsPath ?? "C:\\Users\\david\\PC_AI\\Config\\pcai-tools.json";

        await RunInteractiveAsync(http, baseUrl, model, provider, systemPrompt, stream, react, toolsPath, mode);
        return 0;
    }

    private static void PrintBanner(string baseUrl, string model, string provider, string mode)
    {
        Console.WriteLine("PC_AI Chat TUI");
        Console.WriteLine($"Provider: {provider}");
        Console.WriteLine($"Endpoint: {baseUrl}");
        Console.WriteLine($"Model: {model}");
        Console.WriteLine($"Mode: {mode}");
        Console.WriteLine("Commands: /mode [chat|diagnose], /health, /models, /reset, /exit");
        Console.WriteLine();
    }

    private static string? LoadModePrompt(string mode)
    {
        var path = mode == "diagnose"
            ? "C:\\Users\\david\\PC_AI\\DIAGNOSE.md"
            : "C:\\Users\\david\\PC_AI\\CHAT.md";

        if (File.Exists(path))
        {
            var content = File.ReadAllText(path);
            if (mode == "diagnose")
            {
                var logicPath = "C:\\Users\\david\\PC_AI\\DIAGNOSE_LOGIC.md";
                if (File.Exists(logicPath))
                {
                    content += "\n\n" + File.ReadAllText(logicPath);
                }
            }
            return content;
        }

        return null;
    }

    private static async Task RunInteractiveAsync(
        HttpClient http,
        string baseUrl,
        string model,
        string provider,
        string? systemPrompt,
        bool stream,
        bool react,
        string toolsPath,
        string initialMode)
    {
        var mode = initialMode;
        var history = new List<ChatMessage>();
        if (!string.IsNullOrWhiteSpace(systemPrompt))
        {
            history.Add(new ChatMessage("system", systemPrompt));
            Console.WriteLine("System prompt loaded. Use /reset to clear context.");
        }

        // Initialize persistent PowerShell host for low-latency tool execution
        using var psHost = new PowerShellHost();
        var interlock = new SafetyInterlock(SafetyInterlock.ConsoleConfirmationHandler);
        var toolExecutor = new ToolExecutor(toolsPath, psHost, interlock);
        var openAiClient = new PcaiOpenAiClient(baseUrl);
        var orchestrator = new ReActOrchestrator(openAiClient, toolExecutor, model);

        // Bind orchestration events for TUI feedback
        orchestrator.OnThought += (thought) => Console.WriteLine($"thought> {thought}");
        orchestrator.OnToolCall += (name, args) => Console.WriteLine($"executing> {name}({args})");
        orchestrator.OnToolResult += (name, result) => Console.WriteLine($"result> {name} completed.");
        orchestrator.OnFinalAnswer += (answer) => Console.WriteLine($"assistant> {answer}\n");
        orchestrator.OnError += (error) => Console.WriteLine($"error> {error}");

        while (true)
        {
            Console.Write($"{mode}> ");
            var input = Console.ReadLine();
            if (string.IsNullOrWhiteSpace(input))
            {
                continue;
            }

            if (input.StartsWith("/", StringComparison.OrdinalIgnoreCase))
            {
                if (input.StartsWith("/mode", StringComparison.OrdinalIgnoreCase))
                {
                    var parts = input.Split(' ', 2, StringSplitOptions.RemoveEmptyEntries);
                    if (parts.Length < 2)
                    {
                        Console.WriteLine($"Current mode: {mode}");
                        continue;
                    }

                    var newMode = parts[1].Trim().ToLowerInvariant();
                    if (newMode is "chat" or "diagnose")
                    {
                        mode = newMode;
                        react = newMode == "diagnose";
                        systemPrompt = LoadModePrompt(mode);
                        history.Clear();
                        if (!string.IsNullOrWhiteSpace(systemPrompt))
                        {
                            history.Add(new ChatMessage("system", systemPrompt));
                        }
                        Console.WriteLine($"Switched to {mode} mode. Context reset.");
                        continue;
                    }
                    else
                    {
                        Console.WriteLine("Invalid mode. Use 'chat' or 'diagnose'.");
                        continue;
                    }
                }

                var command = input.Trim().ToLowerInvariant();
                switch (command)
                {
                    case "/exit":
                    case "/quit":
                        return;
                    case "/reset":
                        history.Clear();
                        if (!string.IsNullOrWhiteSpace(systemPrompt))
                        {
                            history.Add(new ChatMessage("system", systemPrompt));
                        }
                        Console.WriteLine("Context cleared.");
                        continue;
                    case "/health":
                        var health = await GetHealthAsync(http, baseUrl, provider);
                        PrintHealth(health, jsonOutput: false);
                        continue;
                    case "/models":
                        var models = await GetModelsAsync(http, baseUrl, provider);
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
                if (react && string.Equals(provider, "vllm", StringComparison.OrdinalIgnoreCase))
                {
                    // Use the unified ReAct orchestrator
                    // We need to inject native context if in diagnose mode
                    if (mode == "diagnose" && PcaiCore.IsAvailable)
                    {
                        var context = PcaiCore.QueryFullContextJson();
                        if (!string.IsNullOrEmpty(context))
                        {
                            var oldContext = history.FirstOrDefault(m => m.Content.Contains("[NATIVE_CONTEXT]"));
                            if (oldContext != null) history.Remove(oldContext);
                            history.Insert(1, new ChatMessage("system", $"[NATIVE_CONTEXT]\n{context}"));
                        }
                    }

                    // Build full prompt from history for the orchestrator
                    // (Orchestrator currently takes a simple prompt, we should enhance it later to take history)
                    var fullPrompt = string.Join("\n", history.Select(m => $"{m.Role}: {m.Content}"));
                    await orchestrator.RunAsync(fullPrompt);
                    continue;
                }

                if (string.Equals(provider, "ollama", StringComparison.OrdinalIgnoreCase))
                {
                    if (stream)
                    {
                        Console.Write("assistant> ");
                        var content = await StreamOllamaChatAsync(http, baseUrl, model, history);
                        history.Add(new ChatMessage("assistant", content));
                    }
                    else
                    {
                        var content = await SendOllamaChatAsync(http, baseUrl, model, history);
                        history.Add(new ChatMessage("assistant", content));
                        Console.WriteLine($"assistant> {content}\n");
                    }
                }
                else
                {
                    var content = await SendOpenAiChatAsync(http, baseUrl, model, history);
                    history.Add(new ChatMessage("assistant", content));
                    Console.WriteLine($"assistant> {content}\n");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"error> {ex.Message}");
            }
        }
    }

    private static async Task RunSingleAsync(
        HttpClient http,
        string baseUrl,
        string model,
        string provider,
        string? systemPrompt,
        string prompt)
    {
        var messages = new List<ChatMessage>();
        if (!string.IsNullOrWhiteSpace(systemPrompt))
        {
            messages.Add(new ChatMessage("system", systemPrompt));
        }
        messages.Add(new ChatMessage("user", prompt));

        if (string.Equals(provider, "ollama", StringComparison.OrdinalIgnoreCase))
        {
            var content = await SendOllamaChatAsync(http, baseUrl, model, messages);
            Console.WriteLine(content);
            return;
        }

        var openAiContent = await SendOpenAiChatAsync(http, baseUrl, model, messages);
        Console.WriteLine(openAiContent);
    }

    private static async Task<HealthResult> GetHealthAsync(HttpClient http, string baseUrl, string provider)
    {
        var result = new HealthResult
        {
            Endpoint = baseUrl,
            Native = PcaiCore.GetDiagnostics()
        };

        try
        {
            if (string.Equals(provider, "ollama", StringComparison.OrdinalIgnoreCase))
            {
                var response = await http.GetFromJsonAsync<OllamaVersion>($"{baseUrl}/api/version", JsonOptions);
                result.Ok = response != null;
                result.Version = response?.Version ?? "unknown";
            }
            else
            {
                var response = await http.GetAsync($"{baseUrl}/v1/models");
                result.Ok = response.IsSuccessStatusCode;
                result.Version = response.IsSuccessStatusCode ? "ok" : "unknown";
            }
        }
        catch (Exception ex)
        {
            result.Ok = false;
            result.Error = ex.Message;
        }

        return result;
    }

    private static async Task<IReadOnlyList<string>> GetModelsAsync(HttpClient http, string baseUrl, string provider)
    {
        if (string.Equals(provider, "ollama", StringComparison.OrdinalIgnoreCase))
        {
            var tags = await http.GetFromJsonAsync<OllamaTags>($"{baseUrl}/api/tags", JsonOptions);
            if (tags?.Models == null)
            {
                return Array.Empty<string>();
            }

            return tags.Models.Select(m => m.Name).ToArray();
        }

        var openAi = await http.GetFromJsonAsync<OpenAiModels>($"{baseUrl}/v1/models", JsonOptions);
        if (openAi?.Data == null)
        {
            return Array.Empty<string>();
        }

        return openAi.Data.Select(m => m.Id).ToArray();
    }

    private static async Task<string> SendOllamaChatAsync(HttpClient http, string baseUrl, string model, List<ChatMessage> messages)
    {
        var request = new OllamaChatRequest
        {
            Model = model,
            Stream = false,
            Messages = messages
        };

        var response = await http.PostAsJsonAsync($"{baseUrl}/api/chat", request, JsonOptions);
        response.EnsureSuccessStatusCode();

        var payload = await response.Content.ReadFromJsonAsync<OllamaChatResponse>(JsonOptions);
        return payload?.Message?.Content ?? string.Empty;
    }

    private static async Task<string> StreamOllamaChatAsync(HttpClient http, string baseUrl, string model, List<ChatMessage> messages)
    {
        var request = new OllamaChatRequest
        {
            Model = model,
            Stream = true,
            Messages = messages
        };

        var json = JsonSerializer.Serialize(request, JsonOptions);
        using var content = new StringContent(json, Encoding.UTF8, "application/json");
        var requestMessage = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/api/chat") { Content = content };
        using var response = await http.SendAsync(requestMessage, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync();
        using var reader = new StreamReader(stream);
        var sb = new StringBuilder();

        while (!reader.EndOfStream)
        {
            var line = await reader.ReadLineAsync();
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            try
            {
                using var doc = JsonDocument.Parse(line);
                if (doc.RootElement.TryGetProperty("message", out var messageElement))
                {
                    var contentText = messageElement.GetProperty("content").GetString() ?? string.Empty;
                    if (!string.IsNullOrEmpty(contentText))
                    {
                        Console.Write(contentText);
                        sb.Append(contentText);
                    }
                }

                if (doc.RootElement.TryGetProperty("done", out var doneElement) && doneElement.GetBoolean())
                {
                    Console.WriteLine();
                    break;
                }
            }
            catch
            {
                continue;
            }
        }

        return sb.ToString();
    }

    private static async Task<string> SendOpenAiChatAsync(HttpClient http, string baseUrl, string model, List<ChatMessage> messages)
    {
        var payload = new
        {
            model,
            messages = messages.Select(m => new { role = m.Role, content = m.Content }).ToArray(),
            temperature = 0.2
        };

        var response = await http.PostAsJsonAsync($"{baseUrl}/v1/chat/completions", payload, JsonOptions);
        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadFromJsonAsync<OpenAiChatResponse>(JsonOptions);
        return json?.Choices?.FirstOrDefault()?.Message?.Content ?? string.Empty;
    }

    private static async Task<OpenAiChatResponse?> SendOpenAiToolCallAsync(HttpClient http, string baseUrl, string model, List<ChatMessage> messages, List<object> tools)
    {
        var payload = new
        {
            model,
            messages = messages.Select(m => new { role = m.Role, content = m.Content }).ToArray(),
            tools = tools,
            tool_choice = "auto",
            temperature = 0.2
        };

        var response = await http.PostAsJsonAsync($"{baseUrl}/v1/chat/completions", payload, JsonOptions);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<OpenAiChatResponse>(JsonOptions);
    }

    private static List<object> LoadTools(string toolsPath)
    {
        if (!File.Exists(toolsPath))
        {
            return new List<object>();
        }

        try
        {
            using var stream = File.OpenRead(toolsPath);
            using var doc = JsonDocument.Parse(stream);
            if (!doc.RootElement.TryGetProperty("tools", out var tools))
            {
                return new List<object>();
            }

            return tools.EnumerateArray()
                .Select(t => JsonSerializer.Deserialize<object>(t.GetRawText(), JsonOptions)!)
                .ToList();
        }
        catch
        {
            return new List<object>();
        }
    }

    private static string ResolveHvsockEndpoint(string url, string? configPath)
    {
        if (!url.StartsWith("hvsock://", StringComparison.OrdinalIgnoreCase) &&
            !url.StartsWith("vsock://", StringComparison.OrdinalIgnoreCase))
        {
            return url;
        }

        var name = url.Split("://", 2, StringSplitOptions.RemoveEmptyEntries).LastOrDefault();
        if (string.IsNullOrWhiteSpace(name))
        {
            return url;
        }

        var path = configPath ?? "C:\\Users\\david\\PC_AI\\Config\\hvsock-proxy.conf";
        if (!File.Exists(path))
        {
            return url;
        }

        foreach (var line in File.ReadAllLines(path))
        {
            var trimmed = line.Trim();
            if (string.IsNullOrWhiteSpace(trimmed) || trimmed.StartsWith("#"))
            {
                continue;
            }

            var parts = trimmed.Split(':');
            if (parts.Length < 4)
            {
                continue;
            }

            if (!string.Equals(parts[0], name, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var host = parts[2];
            var port = parts[3];
            return $"http://{host}:{port}";
        }

        return url;
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
    public string? Provider { get; init; }
    public string? Mode { get; init; }
    public string? Prompt { get; init; }
    public string? ToolsPath { get; init; }
    public string? HvsockConfigPath { get; init; }

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
        string? provider = null;
        string? mode = null;
        string? prompt = null;
        string? toolsPath = null;
        string? hvsockConfigPath = null;

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
                case "--provider":
                    provider = NextValue(args, ref i);
                    break;
                case "--mode":
                    mode = NextValue(args, ref i);
                    break;
                case "--prompt":
                    prompt = NextValue(args, ref i);
                    break;
                case "--tools":
                    toolsPath = NextValue(args, ref i);
                    break;
                case "--hvsock-config":
                    hvsockConfigPath = NextValue(args, ref i);
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
            SystemFile = systemFile,
            Provider = provider,
            Mode = mode,
            Prompt = prompt,
            ToolsPath = toolsPath,
            HvsockConfigPath = hvsockConfigPath
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
    public string? DefaultProvider { get; init; }
    public Dictionary<string, ProviderConfig> Providers { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    public string? ToolsPath { get; init; }
    public string? HvsockConfigPath { get; init; }

    public ProviderConfig? GetProvider(string name)
    {
        if (Providers.TryGetValue(name, out var provider))
        {
            return provider;
        }
        return null;
    }

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

            var providersMap = new Dictionary<string, ProviderConfig>(StringComparer.OrdinalIgnoreCase);
            string? defaultProvider = null;
            string? toolsPath = null;
            var hvsockConfigPath = "C:\\Users\\david\\PC_AI\\Config\\hvsock-proxy.conf";

            if (doc.RootElement.TryGetProperty("providers", out var providers))
            {
                foreach (var provider in providers.EnumerateObject())
                {
                    var providerElement = provider.Value;
                    var baseUrl = providerElement.TryGetProperty("baseUrl", out var baseUrlElement)
                        ? baseUrlElement.GetString()
                        : null;
                    var model = providerElement.TryGetProperty("defaultModel", out var modelElement)
                        ? modelElement.GetString()
                        : null;
                    var timeout = providerElement.TryGetProperty("timeout", out var timeoutElement)
                        ? timeoutElement.GetInt32() / 1000
                        : (int?)null;

                    providersMap[provider.Name] = new ProviderConfig
                    {
                        BaseUrl = baseUrl,
                        DefaultModel = model,
                        TimeoutSec = timeout
                    };
                }
            }

            if (doc.RootElement.TryGetProperty("fallbackOrder", out var fallback))
            {
                defaultProvider = fallback.EnumerateArray().Select(e => e.GetString()).FirstOrDefault(s => !string.IsNullOrWhiteSpace(s));
            }

            if (doc.RootElement.TryGetProperty("router", out var router) &&
                router.TryGetProperty("toolsPath", out var toolsElement))
            {
                toolsPath = toolsElement.GetString();
            }

            return new LlmConfig
            {
                DefaultProvider = defaultProvider,
                ToolsPath = toolsPath,
                HvsockConfigPath = hvsockConfigPath,
                Providers = providersMap
            };
        }
        catch
        {
            return new LlmConfig();
        }
    }
}

public sealed class ProviderConfig
{
    public string? BaseUrl { get; init; }
    public string? DefaultModel { get; init; }
    public int? TimeoutSec { get; init; }
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

public sealed class OpenAiModels
{
    [JsonPropertyName("data")]
    public List<OpenAiModel>? Data { get; set; }
}

public sealed class OpenAiModel
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;
}

public sealed class OpenAiChatResponse
{
    [JsonPropertyName("choices")]
    public List<OpenAiChoice>? Choices { get; set; }
}

public sealed class OpenAiChoice
{
    [JsonPropertyName("message")]
    public OpenAiMessage? Message { get; set; }
}

public sealed class OpenAiMessage
{
    [JsonPropertyName("content")]
    public string Content { get; set; } = string.Empty;

    [JsonPropertyName("tool_calls")]
    public JsonElement? ToolCalls { get; set; }
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

    [JsonPropertyName("tool_call_id")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? ToolCallId { get; set; }

    [JsonPropertyName("tool_calls")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonElement? ToolCalls { get; set; }
}
