using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace PcaiNative;

/// <summary>
/// Executes PC-AI tools defined in pcai-tools.json.
/// Handles mapping from LLM function calls to PowerShell cmdlets or native modules.
/// Includes safety interlocks for destructive actions.
/// </summary>
public sealed class ToolExecutor
{
    private readonly string _toolsPath;
    private readonly JsonNode? _toolsConfig;
    private readonly PowerShellHost? _psHost;
    private readonly SafetyInterlock? _interlock;

    public JsonNode? Tools => _toolsConfig?["tools"];

    public ToolExecutor(string toolsPath, PowerShellHost? psHost = null, SafetyInterlock? interlock = null)
    {
        _toolsPath = toolsPath;
        _psHost = psHost;
        _interlock = interlock;

        if (File.Exists(toolsPath))
        {
            try
            {
                var json = File.ReadAllText(toolsPath);
                _toolsConfig = JsonNode.Parse(json);
            }
            catch
            {
                // Soft failure - caller handles null config
            }
        }
    }

    /// <summary>
    /// Executes a tool call by name and arguments.
    /// </summary>
    public async Task<string> ExecuteToolAsync(string name, JsonElement arguments)
    {
        if (_toolsConfig?["tools"] is not JsonArray tools)
        {
            return "{\"error\": \"Tools configuration not loaded or invalid.\"}";
        }

        var toolDef = tools.FirstOrDefault(t => t?["function"]?["name"]?.ToString() == name);
        if (toolDef == null)
        {
            return $"{{\"error\": \"Unknown tool: {name}\"}}";
        }

        var mapping = toolDef["pcai_mapping"];
        if (mapping == null)
        {
            return $"{{\"error\": \"No mapping found for tool: {name}\"}}";
        }

        // Safety INTERLOCK Check
        if (_interlock != null)
        {
            var isDestructive = mapping["is_destructive"]?.GetValue<bool>() ?? false;
            var description = toolDef["function"]?["description"]?.ToString() ?? "No description available.";

            if (!await _interlock.VerifyActionAsync(name, description, isDestructive))
            {
                return "{\"error\": \"User rejected destructive tool execution.\"}";
            }
        }

        // Special handling for native-first tools to avoid PS overhead
        if (name == "pcai_get_usb_diagnostics" || name == "pcai_get_usb_list")
        {
            return PcaiCore.GetUsbDeepDiagnostics() ?? "{\"error\": \"Native USB diagnostics failed.\"}";
        }
        if (name == "pcai_get_network_info")
        {
            return PcaiCore.GetNetworkThroughput() ?? "{\"error\": \"Native network diagnostics failed.\"}";
        }

        // Standard PowerShell mapping
        var cmdlet = mapping["cmdlet"]?.ToString();
        var module = mapping["module"]?.ToString();

        if (string.IsNullOrEmpty(cmdlet))
        {
            return $"{{\"error\": \"No cmdlet mapped for tool: {name}\"}}";
        }

        if (_psHost != null)
        {
            return await RunHostCommandAsync(cmdlet, module, mapping["params"], arguments);
        }

        return await RunPowerShellCommandAsync(cmdlet, module, mapping["params"], arguments);
    }

    private async Task<string> RunHostCommandAsync(string cmdlet, string? module, JsonNode? paramMappings, JsonElement arguments)
    {
        var sb = new StringBuilder();
        if (!string.IsNullOrEmpty(module))
        {
            sb.Append($"Import-Module '{module}' -ErrorAction SilentlyContinue; ");
        }

        sb.Append(cmdlet);
        AppendParameters(sb, paramMappings, arguments);
        sb.Append(" | ConvertTo-Json -Depth 6 -Compress");

        return await _psHost!.ExecuteAsync(sb.ToString());
    }

    private void AppendParameters(StringBuilder sb, JsonNode? paramMappings, JsonElement arguments)
    {
        if (paramMappings is JsonObject pm)
        {
            foreach (var kvp in pm)
            {
                var pName = kvp.Key;
                var pValue = kvp.Value?.ToString();

                if (pValue != null && pValue.StartsWith("$"))
                {
                    var argName = pValue.TrimStart('$');
                    if (arguments.TryGetProperty(argName, out var argValue))
                    {
                        var valStr = argValue.ValueKind == JsonValueKind.String
                            ? argValue.GetString()
                            : argValue.GetRawText();

                        sb.Append($" -{pName} '{valStr}'");
                    }
                }
                else if (pValue != null)
                {
                    sb.Append($" -{pName} '{pValue}'");
                }
            }
        }
    }

    private async Task<string> RunPowerShellCommandAsync(string cmdlet, string? module, JsonNode? paramMappings, JsonElement arguments)
    {
        var sb = new StringBuilder();
        if (!string.IsNullOrEmpty(module))
        {
            sb.Append($"Import-Module '{module}' -ErrorAction SilentlyContinue; ");
        }

        sb.Append(cmdlet);
        AppendParameters(sb, paramMappings, arguments);

        // Add redirection to ensure clean JSON output
        sb.Append(" | ConvertTo-Json -Depth 6 -Compress");

        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = "pwsh",
                Arguments = $"-NoProfile -NonInteractive -Command \"{sb}\"",
                RedirectStandardOutput = true,
				RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(startInfo);
            if (process == null) return "{\"error\": \"Failed to start PowerShell.\"}";

            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();

            await process.WaitForExitAsync();
            var output = await outputTask;
            var error = await errorTask;

            if (process.ExitCode != 0 && string.IsNullOrWhiteSpace(output))
            {
                return $"{{\"error\": \"PowerShell exited with code {process.ExitCode}: {error}\"}}";
            }

            return string.IsNullOrWhiteSpace(output) ? "{}" : output;
        }
        catch (Exception ex)
        {
            return $"{{\"error\": \"Execution failed: {ex.Message}\"}}";
        }
    }
}
