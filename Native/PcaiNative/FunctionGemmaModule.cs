using System.Text.Json;
using System.Text.Json.Serialization;

namespace PcaiNative;

/// <summary>
/// Report emitted by the FunctionGemma router dataset generator.
/// </summary>
public sealed class FunctionGemmaDatasetReport
{
    [JsonPropertyName("status")]
    public string Status { get; init; } = "";

    [JsonPropertyName("output_jsonl")]
    public string OutputJsonl { get; init; } = "";

    [JsonPropertyName("test_vectors")]
    public string? TestVectors { get; init; }

    [JsonPropertyName("items")]
    public ulong Items { get; init; }

    [JsonPropertyName("vectors")]
    public ulong Vectors { get; init; }

    [JsonPropertyName("elapsed_ms")]
    public ulong ElapsedMs { get; init; }

    [JsonPropertyName("include_tool_coverage")]
    public bool IncludeToolCoverage { get; init; }

    [JsonPropertyName("max_cases")]
    public ulong MaxCases { get; init; }

    public bool IsSuccess => Status == "Success";
}

/// <summary>
/// High-level FunctionGemma dataset utilities backed by the native core DLL.
/// </summary>
public static class FunctionGemmaModule
{
    /// <summary>
    /// Builds the FunctionGemma router dataset + optional test vectors via Rust FFI.
    /// </summary>
    public static FunctionGemmaDatasetReport? BuildRouterDataset(
        string toolsPath,
        string outputJsonl,
        string diagnosePrompt,
        string chatPrompt,
        string? scenariosPath = null,
        string? testVectors = null,
        uint maxCases = 24,
        bool includeToolCoverage = true)
    {
        if (!PcaiCore.IsAvailable) return null;

        var buffer = NativeCore.pcai_build_router_dataset_jsonl(
            toolsPath,
            scenariosPath,
            outputJsonl,
            testVectors,
            diagnosePrompt,
            chatPrompt,
            maxCases,
            includeToolCoverage);

        try
        {
            if (!buffer.IsValid) return null;

            var json = buffer.ToManagedString();
            if (string.IsNullOrEmpty(json)) return null;

            return JsonSerializer.Deserialize<FunctionGemmaDatasetReport>(json);
        }
        finally
        {
            NativeCore.pcai_free_string_buffer(ref buffer);
        }
    }
}
