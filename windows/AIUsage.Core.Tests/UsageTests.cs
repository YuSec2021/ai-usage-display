using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AIUsage.Core;
using Xunit;

namespace AIUsage.Core.Tests;

public sealed class UsageTests : IDisposable
{
    private readonly string root = Path.Combine(Path.GetTempPath(), "ai-usage-fixture-" + Guid.NewGuid().ToString("N"));
    private readonly DateTimeOffset now = DateTimeOffset.UtcNow;
    public UsageTests() { Directory.CreateDirectory(root); }
    public void Dispose() { Directory.Delete(root, true); }
    private string Write(string name, string text)
    {
        var path = Path.Combine(root, name); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text); return path;
    }
    private string Codex(long input, long output, double? used = null, DateTimeOffset? timestamp = null) => JsonSerializer.Serialize(new
    {
        timestamp = (timestamp ?? now).ToString("O"), type = "event_msg",
        payload = new { type = "token_count", info = new { total_token_usage = new { input_tokens = input, output_tokens = output, cached_input_tokens = 10 } },
            rate_limits = used is null ? null : new { primary = new { used_percent = used, window_minutes = 300, resets_at = now.AddHours(1).ToUnixTimeSeconds() } } }
    });

    [Fact] public void CircleUsesOnlyCurrentFiniteFiveHourAndPreservesZero()
    {
        var snapshot = new UsageSnapshot(ProviderId.Codex, [new(10080, 90, now.AddDays(1)), new(300, 0, now.AddHours(1))], now, SourceState.Ready, "fixture");
        Assert.Equal(0, snapshot.FiveHour(now)!.Fraction);
        Assert.Null((snapshot with { Windows = [new(10080, 80, now.AddDays(1))] }).FiveHour(now));
        Assert.Null((snapshot with { Windows = [new(300, 80, now.AddSeconds(-1))] }).FiveHour(now));
        Assert.Null((snapshot with { Windows = [new(300, 0, null, true)] }).FiveHour(now));
        Assert.Null((snapshot with { Windows = [new(300, double.NaN, null)] }).FiveHour(now));
        Assert.Null(snapshot.FiveHour(now.AddHours(6)));
    }

    [Fact] public async Task CodexIncrementalTokensAndTokenOnlyEventsKeepQuota()
    {
        var file = Write("sessions/a.jsonl", Codex(100, 10, 42) + "\n");
        var provider = new LogUsageProvider(ProviderId.Codex, root, clock: () => now);
        var first = await provider.LoadAsync(default);
        Assert.Equal(110, first.History.Single().Tokens.Total);
        Assert.Equal(42, first.Snapshot.FiveHour(now)!.Used);
        File.AppendAllText(file, Codex(160, 25) + "\n");
        var second = await provider.LoadAsync(default);
        Assert.Equal(185, second.History.Single().Tokens.Total);
        Assert.Equal(42, second.Snapshot.FiveHour(now)!.Used);
        Assert.Equal(185, (await provider.LoadAsync(default)).History.Single().Tokens.Total);
    }

    [Fact] public async Task LiveCodexWorksWithoutLogsAndExpiredLogDoesNotBecomeCurrent()
    {
        var provider = new LogUsageProvider(ProviderId.Codex, Path.Combine(root, "missing"),
            liveReader: _ => Task.FromResult<IReadOnlyList<QuotaWindow>?>([new(300, 0, now.AddHours(1))]), clock: () => now);
        Assert.Equal(0, (await provider.LoadAsync(default)).Snapshot.FiveHour(now)!.Used);
        var path = Write("sessions/old.jsonl", Codex(1, 1, 42, now.AddDays(-2)) + "\n");
        var raw = File.ReadAllText(path).Replace(now.AddHours(1).ToUnixTimeSeconds().ToString(), now.AddSeconds(-1).ToUnixTimeSeconds().ToString());
        File.WriteAllText(path, raw);
        var stale = await new LogUsageProvider(ProviderId.Codex, root, clock: () => now).LoadAsync(default);
        Assert.Null(stale.Snapshot.FiveHour(now)); Assert.True(stale.Snapshot.IsStale(now));
    }

    [Fact] public void JsonlRetriesPartialRecordsAndRewrittenFiles()
    {
        var path = Write("partial.jsonl", "{\"a\":");
        var reader = new JsonlReader(); Assert.Empty(reader.Read(path).Lines);
        File.AppendAllText(path, "1}\n"); Assert.Single(reader.Read(path).Lines); Assert.Empty(reader.Read(path).Lines);
        File.WriteAllText(path, "{}\n"); Assert.True(reader.Read(path).Reset);
    }

    [Fact] public void OversizeLineDoesNotTurnItsSuffixIntoAnEvent()
    {
        var path = Write("oversize.jsonl", new string('x', 20));
        var reader = new JsonlReader(initialBytes: 32, maximumLine: 8);
        Assert.Empty(reader.Read(path).Lines);
        File.AppendAllText(path, "{}\n{}\n");
        var batch = reader.Read(path); Assert.Single(batch.Lines); Assert.True(batch.Limited);
    }

    [Fact] public async Task ClaudeDeduplicatesMessagesAndCachesAreNotAddedTwice()
    {
        var line = JsonSerializer.Serialize(new { timestamp = now.ToString("O"), message = new { id = "m1", usage =
            new { input_tokens = 100, output_tokens = 20, cache_read_input_tokens = 40, cache_creation_input_tokens = 30 } } });
        Write("projects/a/session.jsonl", line + "\n" + line + "\n");
        var snapshot = Write("snapshot.json", JsonSerializer.Serialize(new { collected_at = now.ToUnixTimeSeconds(), rate_limits = new
            { five_hour = new { used_percentage = 74, resets_at = now.AddHours(1).ToUnixTimeSeconds() } } }));
        var result = await new LogUsageProvider(ProviderId.Claude, root, snapshot, clock: () => now).LoadAsync(default);
        Assert.Equal(190, result.History.Single().Tokens.Total); Assert.Equal(74, result.Snapshot.FiveHour(now)!.Used);
    }

    [Fact] public async Task KimiIncludesAllSessionsRatherThanCollapsingWireFileNames()
    {
        var line = JsonSerializer.Serialize(new { type = "usage.record", time = now.ToString("O"), usage = new { input_other = 100, input_cache_read = 20, output = 10 } });
        Write("sessions/a/wire.jsonl", line + "\n"); Write("sessions/b/wire.jsonl", line + "\n");
        var result = await new LogUsageProvider(ProviderId.Kimi, root, clock: () => now).LoadAsync(default);
        Assert.Equal(260, result.History.Single().Tokens.Total);
        Assert.Null(result.Snapshot.FiveHour(now));
    }

    [Fact] public void KimiParsesFlexibleNumbersAndRejectsZeroLimit()
    {
        using var json = JsonDocument.Parse("""{"usage":{"limit":"100","remaining":"60","resetTime":"2030-01-01T00:00:00Z"},"limits":[{"window":{"duration":300,"timeUnit":"MINUTE"},"detail":{"limit":10,"used":0}}]}""");
        var windows = QuotaParsers.Kimi(json.RootElement); Assert.Equal(2, windows.Count);
        Assert.Equal(40, windows.Single(window => window.Minutes == 10080).Used);
        Assert.Equal(0, windows.Single(window => window.Minutes == 300).Used);
        using var invalid = JsonDocument.Parse("""{"usage":{"limit":0,"used":0},"limits":[]}""");
        Assert.Empty(QuotaParsers.Kimi(invalid.RootElement));
    }

    [Fact] public async Task KimiCompatiblePromptAlreadyIncludesItsCachedSubset()
    {
        var line = JsonSerializer.Serialize(new { type = "usage.record", time = now.ToString("O"),
            usage = new { prompt_tokens = "100", cached_tokens = "30", output_tokens = "20" } });
        Write("sessions/a/wire.jsonl", line + "\n");
        var result = await new LogUsageProvider(ProviderId.Kimi, root, clock: () => now).LoadAsync(default);
        Assert.Equal(120, result.History.Single().Tokens.Total);
        Assert.Equal(30, result.History.Single().Tokens.Cached);
    }

    [Fact] public async Task KimiHttpUsesOnlyOfficialEndpointAndDoesNotCallWithoutKey()
    {
        var handler = new FixtureHttpHandler(); using var client = new HttpClient(handler);
        Assert.Null(await KimiClient.ReadAsync(client, null, default)); Assert.Equal(0, handler.Calls);
        Assert.Null(await KimiClient.ReadAsync(client, "invalid\r\nheader", default)); Assert.Equal(0, handler.Calls);
        Assert.Single((await KimiClient.ReadAsync(client, "fixture-only-key", default))!);
        Assert.Equal(1, handler.Calls);
    }

    [Fact] public async Task CodexProtocolOnlyUsesReadOnlyHandshakeAndCorrectBucket()
    {
        var response = "{\"id\":0,\"result\":{}}\n" + JsonSerializer.Serialize(new { id = 1, result = new { rateLimitsByLimitId = new
            { codex = new { primary = new { usedPercent = 0, windowDurationMins = 300, resetsAt = now.AddHours(1).ToUnixTimeSeconds() } }, other = new { primary = new { usedPercent = 99 } } } } }) + "\n";
        using var output = new MemoryStream(Encoding.UTF8.GetBytes(response)); using var input = new MemoryStream();
        var windows = await CodexClient.ReadProtocolAsync(output, input, default);
        Assert.Equal(0, Assert.Single(windows!).Used);
        var methods = Encoding.UTF8.GetString(input.ToArray()).Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .Select(line => JsonDocument.Parse(line)).Select(json => json.RootElement.GetProperty("method").GetString()).ToArray();
        Assert.Equal(new[] { "initialize", "initialized", "account/rateLimits/read" }, methods);
    }

    [Fact] public async Task CodexProtocolRejectsOtherBucketsAndHonorsCancellation()
    {
        using var output = new MemoryStream(Encoding.UTF8.GetBytes("{\"id\":0,\"result\":{}}\n{\"id\":1,\"result\":{\"rateLimitsByLimitId\":{\"other\":{\"primary\":{\"usedPercent\":90}}}}}\n"));
        using var input = new MemoryStream(); Assert.Empty((await CodexClient.ReadProtocolAsync(output, input, default))!);
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => CodexClient.ReadProtocolAsync(Stream.Null, new MemoryStream(), cancelled.Token));
    }

    [Fact] public void ClaudeIntegrationRestoresOnlyOwnedConfigurationAndSanitizesInput()
    {
        var settings = Write("claude/settings.json", """{"statusLine":{"type":"command","command":"echo previous"},"other":true}""");
        var config = Path.Combine(root, "collector.json"); var snapshot = Path.Combine(root, "snapshot.json");
        var integration = new ClaudeIntegration(settings, config, "C:/Program Files/O'Brien/AIUsage.exe", snapshot);
        integration.Install(); integration.Install(); Assert.True(integration.IsInstalled());
        var updated = JsonNode.Parse(File.ReadAllText(settings))!; updated["new_setting"] = 42; AtomicJson.Write(settings, updated);
        Assert.True(integration.Uninstall());
        var restored = JsonNode.Parse(File.ReadAllText(settings))!;
        Assert.Equal("echo previous", restored["statusLine"]!["command"]!.GetValue<string>());
        Assert.Equal(42, restored["new_setting"]!.GetValue<int>());
        integration.Install(); updated = JsonNode.Parse(File.ReadAllText(settings))!;
        updated["statusLine"]!["command"] = "echo changed outside"; AtomicJson.Write(settings, updated);
        Assert.False(integration.Uninstall());
        var configuration = JsonSerializer.Deserialize<CollectorConfiguration>(File.ReadAllText(config))!;
        ClaudeIntegration.Collect(Encoding.UTF8.GetBytes("""{"prompt":"private body","session_id":"private-id","rate_limits":{"five_hour":{"used_percentage":0,"resets_at":2000000000}},"api_key":"secret"}"""), configuration, now);
        var text = File.ReadAllText(snapshot); Assert.DoesNotContain("private", text); Assert.DoesNotContain("secret", text);
        Assert.Contains("used_percentage", text); Assert.Contains("'\"'\"'", integration.Command);
    }

    [Fact] public void PreferencesAndPlacementRecoverWithinVisibleWorkArea()
    {
        var path = Write("settings.json", "{" ); var preferences = AtomicJson.ReadPreferences(path);
        Assert.Equal(4, preferences.VisibleProviders().Count); Assert.Single(Directory.GetFiles(root, "*.corrupt-*"));
        preferences.Selected = []; AtomicJson.Write(path, preferences); Assert.Empty(AtomicJson.ReadPreferences(path).VisibleProviders());
        var moved = new WindowPlacement(3000, -100, 300, 60).Fit(new(0, 0, 1920, 1040));
        Assert.Equal(1620, moved.X); Assert.Equal(0, moved.Y);
        var snapped = new WindowPlacement(7, 7, 300, 60).Fit(new(0, 0, 1920, 1040)); Assert.Equal(0, snapped.X);
        var negative = new WindowPlacement(-3000, 1000, 300, 60).Fit(new(-1920, 0, 1920, 1080)); Assert.Equal(-1920, negative.X);
    }

    [Fact] public async Task MonitorQueuesRefreshAndRejectsResultsInvalidatedByKeyChange()
    {
        var provider = new DelayedProvider(now); using var monitor = new UsageMonitor([provider]);
        var first = monitor.RefreshAsync(); await provider.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        monitor.Invalidate(ProviderId.Kimi); provider.Release.SetResult();
        await first.WaitAsync(TimeSpan.FromSeconds(3));
        Assert.Equal(2, provider.Calls); Assert.Equal(22, monitor.Snapshots.Single().FiveHour(now)!.Used);
    }

    [Fact] public async Task DeselectedProvidersDoNotPerformNetworkOrLogWork()
    {
        var provider = new DelayedProvider(now); using var monitor = new UsageMonitor([provider], _ => false);
        await monitor.RefreshAsync(); Assert.Equal(0, provider.Calls);
    }

    [Fact] public void FloatingPresentationFormatsCountdownUpdatedAgeAndColors()
    {
        var claude = new UsageSnapshot(ProviderId.Claude, [new(300, 68, now.AddHours(2).AddMinutes(18))], now.AddSeconds(-20), SourceState.Ready, "ok");
        Assert.Equal("2 小时 18 分钟后重置", FloatingPresentation.FormatResetCountdown(claude, now));
        Assert.Equal("刚刚更新", FloatingPresentation.FormatUpdatedAge(claude, now));
        Assert.Equal("#F58A12", FloatingPresentation.RingColor(claude, now));

        var high = new UsageSnapshot(ProviderId.Codex, [new(300, 92, now.AddMinutes(25))], now.AddMinutes(-5), SourceState.Ready, "ok");
        Assert.Equal("25 分钟后重置", FloatingPresentation.FormatResetCountdown(high, now));
        Assert.Equal("5 分钟前更新", FloatingPresentation.FormatUpdatedAge(high, now));
        Assert.Equal("#E84141", FloatingPresentation.RingColor(high, now));

        var minimax = UsageSnapshot.Empty(ProviderId.MiniMax, SourceState.Unsupported, "Windows 缓存格式尚未验证，首版暂不支持");
        Assert.Equal("Windows 端暂不支持", FloatingPresentation.FormatResetCountdown(minimax, now));
        Assert.Equal("暂无数据", FloatingPresentation.FormatUpdatedAge(minimax, now));
        Assert.Equal("#8B99AF", FloatingPresentation.RingColor(minimax, now));
    }

    [Fact] public void FloatingLayoutComputesDockSizePopoverFlipAndArrowAlignment()
    {
        Assert.Equal((256, 64), FloatingLayout.ComputeDockSize(4));
        Assert.Equal(41, FloatingLayout.RingCenterX(256, 4, 0), 2);
        Assert.Equal(215, FloatingLayout.RingCenterX(256, 4, 3), 2);

        var work = new WindowPlacement(0, 0, 1920, 1040);
        var bottomDock = new WindowPlacement(1600, 950, 256, 64);
        var above = FloatingLayout.PlacePopover(bottomDock, work, 240, 106, 10, FloatingLayout.RingCenterX(256, 4, 1));
        Assert.True(above.PlacedAbove);
        Assert.Equal(950 - 10 - 106, above.Bounds.Y);
        Assert.InRange(above.ArrowOffsetPx, 22, 218);

        var topDock = new WindowPlacement(100, 12, 256, 64);
        var below = FloatingLayout.PlacePopover(topDock, work, 240, 106, 10, FloatingLayout.RingCenterX(256, 4, 0));
        Assert.False(below.PlacedAbove);
        Assert.Equal(12 + 64 + 10, below.Bounds.Y);
    }

    [Theory]
    [InlineData(1.0)]
    [InlineData(1.25)]
    [InlineData(1.5)]
    [InlineData(2.0)]
    public void FloatingCaretKeepsItsOwnSpaceAndTracksEveryRingAtEachDpi(double scale)
    {
        var work = new WindowPlacement(0, 0, 6000, 4000);
        var cardHeight = (int)Math.Round(FloatingLayout.PopoverCardHeight * scale);
        var caretHeight = (int)Math.Round(FloatingLayout.CaretHeight * scale);
        var height = (int)Math.Round(FloatingLayout.PopoverHeight * scale);
        var width = (int)Math.Round(FloatingLayout.PopoverWidth * scale);
        var gap = (int)Math.Round(FloatingLayout.PopoverGap * scale);
        Assert.InRange(height - cardHeight, caretHeight - 1, caretHeight + 1);
        for (var count = 1; count <= 4; count++)
        {
            var size = FloatingLayout.ComputeDockSize(count);
            for (var index = 0; index < count; index++)
            {
                var center = FloatingLayout.RingCenterX(size.Width, count, index) * scale;
                foreach (var y in new[] { 0, 1000 })
                {
                    var dock = new WindowPlacement(1000, y, (int)Math.Round(size.Width * scale), (int)Math.Round(size.Height * scale));
                    var placement = FloatingLayout.PlacePopover(dock, work, width, height, gap, center, 22 * scale);
                    Assert.Equal(dock.X + center, placement.Bounds.X + placement.ArrowOffsetPx, 3);
                    Assert.Equal(y > 0, placement.PlacedAbove);
                    if (placement.PlacedAbove) Assert.Equal(gap, dock.Y - placement.Bounds.Y - placement.Bounds.Height);
                    else Assert.Equal(gap, placement.Bounds.Y - dock.Y - dock.Height);
                }
            }
        }
    }

    private sealed class DelayedProvider(DateTimeOffset now) : IUsageProvider
    {
        public ProviderId Id => ProviderId.Kimi;
        public int Calls;
        public TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<ProviderResult> LoadAsync(CancellationToken cancellationToken)
        {
            var call = Interlocked.Increment(ref Calls); Started.TrySetResult();
            if (call == 1) await Release.Task.WaitAsync(cancellationToken);
            return new(new(Id, [new(300, call == 1 ? 11 : 22, now.AddHours(1))], now, SourceState.Ready, "fixture"), []);
        }
    }

    private sealed class FixtureHttpHandler : HttpMessageHandler
    {
        public int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++; Assert.Equal("https://api.kimi.com/coding/v1/usages", request.RequestUri!.ToString());
            Assert.Equal("Bearer", request.Headers.Authorization!.Scheme);
            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK) { Content = new StringContent(
                """{"usage":{"limit":100,"used":20},"limits":[]}""") });
        }
    }
}
