using System.Text.Json;

namespace AIUsage.Core;

public sealed class LogUsageProvider : IUsageProvider
{
    private sealed class FileState
    {
        public TokenUsage? Total;
        public readonly Dictionary<DateOnly, TokenUsage> Daily = [];
        public readonly Dictionary<string, (DateOnly Day, TokenUsage Tokens)> Messages = [];
        public IReadOnlyList<QuotaWindow> Windows = [];
        public DateTimeOffset Observed;
        public bool Limited;
    }
    public ProviderId Id { get; }
    private readonly string directory;
    private readonly string? snapshotPath;
    private readonly Func<CancellationToken, Task<IReadOnlyList<QuotaWindow>?>>? liveReader;
    private readonly Func<DateTimeOffset> clock;
    private readonly TimeZoneInfo timeZone;
    private readonly JsonlReader reader;
    private readonly Dictionary<string, FileState> states = new(StringComparer.OrdinalIgnoreCase);

    public LogUsageProvider(ProviderId id, string directory, string? snapshotPath = null,
        Func<CancellationToken, Task<IReadOnlyList<QuotaWindow>?>>? liveReader = null,
        Func<DateTimeOffset>? clock = null, JsonlReader? reader = null, TimeZoneInfo? timeZone = null)
    {
        Id = id; this.directory = directory; this.snapshotPath = snapshotPath;
        this.liveReader = liveReader; this.clock = clock ?? (() => DateTimeOffset.UtcNow);
        this.reader = reader ?? new(); this.timeZone = timeZone ?? TimeZoneInfo.Local;
    }

    public async Task<ProviderResult> LoadAsync(CancellationToken cancellationToken)
    {
        if (Id == ProviderId.MiniMax)
            return new(UsageSnapshot.Empty(Id, SourceState.Unsupported, "Windows 缓存格式尚未验证，首版暂不支持"), []);
        var now = clock();
        var cutoff = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(now, timeZone).DateTime).AddDays(-6);
        var roots = Id switch
        {
            ProviderId.Codex => new[] { Path.Combine(directory, "sessions"), Path.Combine(directory, "archived_sessions") },
            ProviderId.Claude => [Path.Combine(directory, "projects")],
            _ => [Path.Combine(directory, "sessions")]
        };
        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
        var discovered = roots.Where(Directory.Exists).SelectMany(root => Directory.EnumerateFiles(root, "*.jsonl", options))
            .Where(path => Id != ProviderId.Kimi || Path.GetFileName(path) == "wire.jsonl")
            .Select(path => new FileInfo(path)).OrderByDescending(file => file.LastWriteTimeUtc).Take(1601).ToArray();
        var fileLimit = discovered.Length > 1600;
        var candidates = discovered.Where((file, index) => index == 0 || file.LastWriteTimeUtc >= now.AddDays(-7).UtcDateTime);
        var files = candidates.Take(1600).GroupBy(file => Id == ProviderId.Codex ? file.Name : file.FullName, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First().FullName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var removed in states.Keys.Where(path => !files.Contains(path)).ToArray()) states.Remove(removed);
        reader.Retain(files);
        var readFailed = false;
        long bytesRead = 0;
        foreach (var path in files)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                if (bytesRead >= 64 * 1024 * 1024) { fileLimit = true; break; }
                var batch = reader.Read(path);
                bytesRead += batch.BytesRead;
                if (batch.Reset || !states.ContainsKey(path)) states[path] = new();
                var state = states[path];
                state.Limited |= batch.Limited;
                foreach (var line in batch.Lines) Consume(line, state, cutoff);
                foreach (var day in state.Daily.Keys.Where(day => day < cutoff).ToArray()) state.Daily.Remove(day);
                foreach (var key in state.Messages.Where(item => item.Value.Day < cutoff).Select(item => item.Key).ToArray()) state.Messages.Remove(key);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { readFailed = true; }
        }
        var history = new Dictionary<DateOnly, TokenUsage>();
        foreach (var state in states.Values)
        {
            foreach (var (day, tokens) in state.Daily) history[day] = history.GetValueOrDefault(day, new()) + tokens;
            foreach (var (_, (day, tokens)) in state.Messages) history[day] = history.GetValueOrDefault(day, new()) + tokens;
        }
        var latest = states.Values.Where(state => state.Windows.Count > 0).MaxBy(state => state.Observed);
        IReadOnlyList<QuotaWindow> windows = latest?.Windows ?? [];
        var observed = latest?.Observed ?? now;
        if (Id == ProviderId.Claude && snapshotPath is not null && File.Exists(snapshotPath))
        {
            try
            {
                using var snapshot = AtomicJson.Read(snapshotPath);
                var value = snapshot.RootElement;
                windows = QuotaParsers.Claude(value.Field("rate_limits"));
                observed = value.Field("collected_at").Timestamp() ?? new DateTimeOffset(File.GetLastWriteTimeUtc(snapshotPath));
            }
            catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException) { readFailed = true; }
        }
        if (liveReader is not null)
        {
            var live = await liveReader(cancellationToken);
            if (live is { Count: > 0 }) { windows = live; observed = now; }
        }
        var stateValue = windows.Count > 0 ? SourceState.Ready : history.Count > 0 ? SourceState.Ready :
            !Directory.Exists(directory) ? SourceState.Missing : Id == ProviderId.Claude ? SourceState.IntegrationRequired : SourceState.Waiting;
        var message = windows.Count > 0 ? "额度数据已更新" : Id switch
        {
            ProviderId.Claude => "在设置中安装 Claude 集成，完成一次对话后更新额度",
            ProviderId.Kimi => "本地 Token 可独立使用；配置 Kimi API Key 后读取额度",
            _ => "等待本地用量；安装并登录 Codex CLI 可主动读取额度"
        };
        if (readFailed) { stateValue = SourceState.Stale; message = "部分用量文件暂不可读，保留上次有效数据"; }
        var limited = fileLimit || states.Values.Any(state => state.Limited);
        return new(new(Id, windows, observed, stateValue, message, limited),
            history.Where(item => item.Key >= cutoff).OrderBy(item => item.Key).Select(item => new DailyUsage(item.Key, Id, item.Value)).ToArray());
    }

    private void Consume(byte[] line, FileState state, DateOnly cutoff)
    {
        try
        {
            using var json = JsonDocument.Parse(line, new JsonDocumentOptions { MaxDepth = 64 });
            var value = json.RootElement;
            var date = (value.Field("timestamp").Timestamp() ?? value.Field("time").Timestamp());
            if (date is null) return;
            var day = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(date.Value, timeZone).DateTime);
            if (Id == ProviderId.Codex)
            {
                var payload = value.Field("payload");
                if (value.Field("type").Text() != "event_msg" || payload.Field("type").Text() != "token_count") return;
                var total = payload.Field("info").Field("total_token_usage");
                if (total.ValueKind == JsonValueKind.Object)
                {
                    var current = QuotaParsers.Tokens(total);
                    var delta = state.Total is { } old ? current.Delta(old) : current;
                    state.Total = current;
                    if (day >= cutoff) state.Daily[day] = state.Daily.GetValueOrDefault(day, new()) + delta;
                }
                var windows = QuotaParsers.Codex(payload.Field("rate_limits"), false);
                if (windows.Count > 0 && date >= state.Observed) { state.Windows = windows; state.Observed = date.Value; }
            }
            else if (Id == ProviderId.Claude)
            {
                var message = value.Field("message");
                var id = message.Field("id").Text();
                var usage = message.Field("usage");
                if (id is not null && day >= cutoff && usage.ValueKind == JsonValueKind.Object)
                    state.Messages[id] = (day, QuotaParsers.Tokens(usage, true));
            }
            else
            {
                JsonElement usage;
                string? id = null;
                if (value.Field("type").Text() == "usage.record") usage = value.Field("usage");
                else
                {
                    var message = value.Field("message");
                    if (message.Field("type").Text() != "StatusUpdate") return;
                    usage = message.Field("payload").Field("token_usage");
                    id = message.Field("payload").Field("message_id").Text();
                }
                if (usage.ValueKind != JsonValueKind.Object || day < cutoff) return;
                long? Optional(params string[] names) => names.Select(name => usage.Field(name).Integer()).FirstOrDefault(count => count.HasValue);
                long Number(params string[] names) => Optional(names) ?? 0;
                var cache = TokenUsage.Add(Number("inputCacheRead", "input_cache_read", "cache_read_input_tokens", "cache_read_tokens"),
                    Number("inputCacheCreation", "input_cache_creation", "cache_creation_input_tokens"));
                var input = Optional("prompt_tokens") ?? TokenUsage.Add(Number("inputOther", "input_other", "input_tokens"), cache);
                var tokens = new TokenUsage(input, Optional("cached_tokens") ?? cache, Number("output", "output_tokens", "completion_tokens"));
                if (id is null) state.Daily[day] = state.Daily.GetValueOrDefault(day, new()) + tokens;
                else state.Messages[id] = (day, tokens);
            }
        }
        catch (JsonException) { /* A malformed event cannot erase a previously valid quota. */ }
    }
}
