using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using AIUsage.Core;
using Xunit;

namespace AIUsage.Core.Tests;

public sealed class SharedFixtureTests
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private static string SharedFixturesRoot => Path.Combine(AppContext.BaseDirectory, "Fixtures", "shared");

    public static IEnumerable<object[]> SharedCases()
    {
        var root = SharedFixturesRoot;
        if (!Directory.Exists(root))
            yield break;

        foreach (var providerDir in Directory.EnumerateDirectories(root).OrderBy(Path.GetFileName, StringComparer.Ordinal))
        {
            var provider = Path.GetFileName(providerDir);
            foreach (var caseDir in Directory.EnumerateDirectories(providerDir).OrderBy(Path.GetFileName, StringComparer.Ordinal))
            {
                var caseName = Path.GetFileName(caseDir);
                yield return [provider, caseName, caseDir];
            }
        }
    }

    [Fact]
    public void SharedFixtureDirectoryContainsAllProviders()
    {
        Assert.True(Directory.Exists(SharedFixturesRoot), $"Shared fixtures root not found: {SharedFixturesRoot}");
        var cases = SharedCases().ToList();
        Assert.NotEmpty(cases);
        var providers = cases.Select(item => (string)item[0]).ToHashSet(StringComparer.Ordinal);
        Assert.Contains("codex", providers);
        Assert.Contains("claude", providers);
        Assert.Contains("kimi", providers);
    }

    [Theory]
    [MemberData(nameof(SharedCases))]
    public async Task SharedFixtureMatchesExpected(string providerName, string caseName, string caseDir)
    {
        var label = $"{providerName}/{caseName}";
        var expectedPath = Path.Combine(caseDir, "expected.json");
        Assert.True(File.Exists(expectedPath), $"[{label}] Missing expected.json at {expectedPath}");

        var expected = JsonSerializer.Deserialize<ExpectedFixture>(File.ReadAllText(expectedPath), JsonOptions);
        Assert.NotNull(expected);
        Assert.Equal(1, expected!.SchemaVersion);
        Assert.Equal(providerName, expected.Provider);
        Assert.Equal(caseName, expected.Case);

        var now = DateTimeOffset.Parse(expected.Now, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
        var timeZone = TimeZoneInfo.FindSystemTimeZoneById(expected.TimeZone);
        var providerId = ParseProviderId(expected.Provider, label);

        var tempRoot = Path.Combine(Path.GetTempPath(), $"ai-usage-shared-{providerName}-{caseName}-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);
        try
        {
            var sourceInput = Path.Combine(caseDir, "input");
            Assert.True(Directory.Exists(sourceInput), $"[{label}] Missing input/ directory at {sourceInput}");

            var targetInput = Path.Combine(tempRoot, "input");
            CopyDirectoryWithTimestamp(sourceInput, targetInput, now.UtcDateTime);

            string? snapshotPath = null;
            var sourceSnapshot = Path.Combine(caseDir, "claude-snapshot.json");
            if (File.Exists(sourceSnapshot))
            {
                snapshotPath = Path.Combine(tempRoot, "claude-snapshot.json");
                File.Copy(sourceSnapshot, snapshotPath, overwrite: true);
                File.SetLastWriteTimeUtc(snapshotPath, now.UtcDateTime);
            }

            Func<CancellationToken, Task<IReadOnlyList<QuotaWindow>?>>? liveReader = null;
            var sourceKimiApi = Path.Combine(caseDir, "kimi-usage-api.json");
            if (File.Exists(sourceKimiApi))
            {
                var rawApiJson = File.ReadAllText(sourceKimiApi);
                liveReader = _ =>
                {
                    using var doc = JsonDocument.Parse(rawApiJson);
                    return Task.FromResult<IReadOnlyList<QuotaWindow>?>(QuotaParsers.Kimi(doc.RootElement));
                };
            }

            var provider = new LogUsageProvider(
                providerId,
                targetInput,
                snapshotPath: snapshotPath,
                liveReader: liveReader,
                clock: () => now,
                timeZone: timeZone);

            var result = await provider.LoadAsync(default);

            var exemption = expected.PlatformExemptions?.Windows;
            if (exemption is not null)
            {
                Assert.False(string.IsNullOrWhiteSpace(exemption.Reason), $"[{label}] platformExemptions.windows.reason must be non-empty");
            }

            var expectedState = exemption?.State ?? expected.State;
            var expectedDaily = exemption?.DailyUsage ?? expected.DailyUsage;
            var expectedWindows = exemption?.QuotaWindows ?? expected.QuotaWindows;
            var exemptionNote = exemption is null ? string.Empty : $" (windows exemption: {exemption.Reason})";

            // 1. State
            var actualState = MapSourceState(result.Snapshot.State);
            Assert.True(
                string.Equals(expectedState, actualState, StringComparison.Ordinal),
                $"[{label}] State mismatch{exemptionNote}: expected '{expectedState}', actual '{actualState}' (raw: {result.Snapshot.State})");

            // 2. Daily usage (sorted by YYYY-MM-DD ascending, exact integer match)
            var actualDaily = result.History
                .OrderBy(item => item.Date)
                .Select(item => new ExpectedDailyUsage
                {
                    Date = item.Date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                    Tokens = new ExpectedTokens
                    {
                        Input = item.Tokens.Input,
                        Cached = item.Tokens.Cached,
                        Output = item.Tokens.Output
                    }
                })
                .ToList();

            var orderedExpectedDaily = expectedDaily
                .OrderBy(item => item.Date, StringComparer.Ordinal)
                .ToList();

            Assert.True(
                orderedExpectedDaily.Count == actualDaily.Count,
                $"[{label}] DailyUsage count mismatch{exemptionNote}: expected {orderedExpectedDaily.Count} ({FormatDaily(orderedExpectedDaily)}), actual {actualDaily.Count} ({FormatDaily(actualDaily)})");

            for (var i = 0; i < orderedExpectedDaily.Count; i++)
            {
                var exp = orderedExpectedDaily[i];
                var act = actualDaily[i];
                Assert.True(
                    exp.Date == act.Date &&
                    exp.Tokens.Input == act.Tokens.Input &&
                    exp.Tokens.Cached == act.Tokens.Cached &&
                    exp.Tokens.Output == act.Tokens.Output,
                    $"[{label}] DailyUsage[{i}] mismatch{exemptionNote}: expected ({exp.Date}: in={exp.Tokens.Input}, cached={exp.Tokens.Cached}, out={exp.Tokens.Output}), actual ({act.Date}: in={act.Tokens.Input}, cached={act.Tokens.Cached}, out={act.Tokens.Output})");
            }

            // 3. Quota windows (sorted by (minutes ?? int.MaxValue, usedPercent), tolerances: 0.01% / 1.0s)
            var normalizedActualWindows = result.Snapshot.Windows
                .Select(w => new NormalizedWindow(
                    w.Minutes == 0 ? null : w.Minutes,
                    w.Used,
                    w.ResetsAt))
                .OrderBy(w => w.Minutes ?? int.MaxValue)
                .ThenBy(w => w.UsedPercent)
                .ToList();

            var normalizedExpectedWindows = expectedWindows
                .Select(w => new NormalizedWindow(
                    w.Minutes,
                    w.UsedPercent,
                    string.IsNullOrWhiteSpace(w.ResetsAt)
                        ? null
                        : DateTimeOffset.Parse(w.ResetsAt, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind)))
                .OrderBy(w => w.Minutes ?? int.MaxValue)
                .ThenBy(w => w.UsedPercent)
                .ToList();

            Assert.True(
                normalizedExpectedWindows.Count == normalizedActualWindows.Count,
                $"[{label}] QuotaWindows count mismatch{exemptionNote}: expected {normalizedExpectedWindows.Count}, actual {normalizedActualWindows.Count}");

            for (var i = 0; i < normalizedExpectedWindows.Count; i++)
            {
                var exp = normalizedExpectedWindows[i];
                var act = normalizedActualWindows[i];

                Assert.True(
                    exp.Minutes == act.Minutes,
                    $"[{label}] QuotaWindows[{i}].minutes mismatch{exemptionNote}: expected {exp.Minutes?.ToString() ?? "null"}, actual {act.Minutes?.ToString() ?? "null"}");

                var percentDiff = Math.Abs(act.UsedPercent - exp.UsedPercent);
                Assert.True(
                    percentDiff <= 0.01,
                    $"[{label}] QuotaWindows[{i}].usedPercent mismatch{exemptionNote}: expected {exp.UsedPercent}, actual {act.UsedPercent} (diff {percentDiff:F6} > 0.01)");

                if (exp.ResetsAt is null && act.ResetsAt is null)
                {
                    continue;
                }

                Assert.True(
                    exp.ResetsAt is not null && act.ResetsAt is not null,
                    $"[{label}] QuotaWindows[{i}].resetsAt nullability mismatch{exemptionNote}: expected {exp.ResetsAt?.ToString("O") ?? "null"}, actual {act.ResetsAt?.ToString("O") ?? "null"}");

                var secondsDiff = Math.Abs((act.ResetsAt!.Value - exp.ResetsAt!.Value).TotalSeconds);
                Assert.True(
                    secondsDiff <= 1.0,
                    $"[{label}] QuotaWindows[{i}].resetsAt mismatch{exemptionNote}: expected {exp.ResetsAt:O}, actual {act.ResetsAt:O} (diff {secondsDiff:F3}s > 1.0s)");
            }
        }
        finally
        {
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    private static ProviderId ParseProviderId(string provider, string label) => provider switch
    {
        "codex" => ProviderId.Codex,
        "claude" => ProviderId.Claude,
        "kimi" => ProviderId.Kimi,
        _ => throw new InvalidOperationException($"[{label}] Unsupported shared fixture provider: {provider}")
    };

    private static string MapSourceState(SourceState state) => state switch
    {
        SourceState.Ready => "ready",
        SourceState.Stale => "stale",
        SourceState.Waiting => "waiting",
        SourceState.Missing => "missing",
        SourceState.IntegrationRequired => "integrationRequired",
        SourceState.Unsupported => "unsupportedFormat",
        SourceState.Failed => "failed",
        _ => throw new ArgumentOutOfRangeException(nameof(state), state, null)
    };

    private static void CopyDirectoryWithTimestamp(string sourceDir, string targetDir, DateTime lastWriteUtc)
    {
        Directory.CreateDirectory(targetDir);
        foreach (var file in Directory.EnumerateFiles(sourceDir))
        {
            var dest = Path.Combine(targetDir, Path.GetFileName(file));
            File.Copy(file, dest, overwrite: true);
            File.SetLastWriteTimeUtc(dest, lastWriteUtc);
        }
        foreach (var dir in Directory.EnumerateDirectories(sourceDir))
        {
            CopyDirectoryWithTimestamp(dir, Path.Combine(targetDir, Path.GetFileName(dir)), lastWriteUtc);
        }
    }

    private static string FormatDaily(IEnumerable<ExpectedDailyUsage> items) =>
        string.Join(", ", items.Select(d => $"{d.Date}:({d.Tokens.Input}/{d.Tokens.Cached}/{d.Tokens.Output})"));

    private sealed record NormalizedWindow(int? Minutes, double UsedPercent, DateTimeOffset? ResetsAt);

    private sealed class ExpectedFixture
    {
        [JsonPropertyName("schemaVersion")] public int SchemaVersion { get; set; }
        [JsonPropertyName("provider")] public string Provider { get; set; } = string.Empty;
        [JsonPropertyName("case")] public string Case { get; set; } = string.Empty;
        [JsonPropertyName("description")] public string Description { get; set; } = string.Empty;
        [JsonPropertyName("now")] public string Now { get; set; } = string.Empty;
        [JsonPropertyName("timeZone")] public string TimeZone { get; set; } = "UTC";
        [JsonPropertyName("dailyUsage")] public List<ExpectedDailyUsage> DailyUsage { get; set; } = [];
        [JsonPropertyName("quotaWindows")] public List<ExpectedQuotaWindow> QuotaWindows { get; set; } = [];
        [JsonPropertyName("state")] public string State { get; set; } = string.Empty;
        [JsonPropertyName("platformExemptions")] public PlatformExemptions? PlatformExemptions { get; set; }
    }

    private sealed class PlatformExemptions
    {
        [JsonPropertyName("macos")] public PlatformExemption? MacOS { get; set; }
        [JsonPropertyName("windows")] public PlatformExemption? Windows { get; set; }
    }

    private sealed class PlatformExemption
    {
        [JsonPropertyName("reason")] public string Reason { get; set; } = string.Empty;
        [JsonPropertyName("dailyUsage")] public List<ExpectedDailyUsage>? DailyUsage { get; set; }
        [JsonPropertyName("quotaWindows")] public List<ExpectedQuotaWindow>? QuotaWindows { get; set; }
        [JsonPropertyName("state")] public string? State { get; set; }
    }

    private sealed class ExpectedDailyUsage
    {
        [JsonPropertyName("date")] public string Date { get; set; } = string.Empty;
        [JsonPropertyName("tokens")] public ExpectedTokens Tokens { get; set; } = new();
    }

    private sealed class ExpectedTokens
    {
        [JsonPropertyName("input")] public long Input { get; set; }
        [JsonPropertyName("cached")] public long Cached { get; set; }
        [JsonPropertyName("output")] public long Output { get; set; }
    }

    private sealed class ExpectedQuotaWindow
    {
        [JsonPropertyName("minutes")] public int? Minutes { get; set; }
        [JsonPropertyName("usedPercent")] public double UsedPercent { get; set; }
        [JsonPropertyName("resetsAt")] public string? ResetsAt { get; set; }
    }
}
