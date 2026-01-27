using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;

namespace PcaiNative
{
    public sealed class HelpEntry
    {
        public string Name { get; set; } = string.Empty;
        public string Synopsis { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public List<string> Examples { get; set; } = new();
        public string SourcePath { get; set; } = string.Empty;
        public Dictionary<string, string> Parameters { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    }

    public static class HelpExtractor
    {
        private static readonly Regex HelpBlockRegex = new(
            "(?s)<#(.*?)#>\\s*function\\s+([A-Za-z0-9_-]+)",
            RegexOptions.Compiled | RegexOptions.Multiline | RegexOptions.Singleline);

        private static readonly Regex SynopsisRegex = new(
            "(?ms)^\\s*\\.SYNOPSIS\\s*(?<syn>.+?)(?=^\\s*\\.[A-Z]|\\z)",
            RegexOptions.Compiled | RegexOptions.Multiline | RegexOptions.Singleline);

        private static readonly Regex DescriptionRegex = new(
            "(?ms)^\\s*\\.DESCRIPTION\\s*(?<desc>.+?)(?=^\\s*\\.[A-Z]|\\z)",
            RegexOptions.Compiled | RegexOptions.Multiline | RegexOptions.Singleline);

        private static readonly Regex ParameterRegex = new(
            "(?ms)^\\s*\\.PARAMETER\\s+(?<name>\\S+)\\s*(?<desc>.+?)(?=^\\s*\\.[A-Z]|\\z)",
            RegexOptions.Compiled | RegexOptions.Multiline | RegexOptions.Singleline);

        private static readonly Regex ExampleRegex = new(
            "(?ms)^\\s*\\.EXAMPLE\\s*(?<example>.+?)(?=^\\s*\\.[A-Z]|\\z)",
            RegexOptions.Compiled | RegexOptions.Multiline | RegexOptions.Singleline);

        public static List<HelpEntry> ExtractFromFile(string path)
        {
            var entries = new List<HelpEntry>();
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
            {
                return entries;
            }

            string content;
            try
            {
                content = File.ReadAllText(path);
            }
            catch
            {
                return entries;
            }

            var matches = HelpBlockRegex.Matches(content);
            foreach (Match match in matches)
            {
                if (!match.Success || match.Groups.Count < 3)
                {
                    continue;
                }

                var block = match.Groups[1].Value;
                var name = match.Groups[2].Value;

                var synopsisMatch = SynopsisRegex.Match(block);
                var descriptionMatch = DescriptionRegex.Match(block);
                var parameterMatches = ParameterRegex.Matches(block);
                var exampleMatches = ExampleRegex.Matches(block);

                var synopsis = synopsisMatch.Success ? synopsisMatch.Groups["syn"].Value.Trim() : string.Empty;
                var description = descriptionMatch.Success ? descriptionMatch.Groups["desc"].Value.Trim() : string.Empty;
                var parameters = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (Match parameterMatch in parameterMatches)
                {
                    var paramName = parameterMatch.Groups["name"].Value.Trim();
                    var paramDesc = parameterMatch.Groups["desc"].Value.Trim();
                    if (!string.IsNullOrWhiteSpace(paramName))
                    {
                        parameters[paramName] = paramDesc;
                    }
                }

                var examples = new List<string>();
                foreach (Match exampleMatch in exampleMatches)
                {
                    var example = exampleMatch.Groups["example"].Value.Trim();
                    if (!string.IsNullOrWhiteSpace(example))
                    {
                        examples.Add(example);
                    }
                }

                entries.Add(new HelpEntry
                {
                    Name = name,
                    Synopsis = synopsis,
                    Description = description,
                    Examples = examples,
                    SourcePath = path,
                    Parameters = parameters
                });
            }

            return entries;
        }

        public static List<HelpEntry> ExtractFromFiles(string[] paths)
        {
            var results = new List<HelpEntry>();
            if (paths == null || paths.Length == 0)
            {
                return results;
            }

            foreach (var path in paths)
            {
                results.AddRange(ExtractFromFile(path));
            }

            return results;
        }
    }
}
