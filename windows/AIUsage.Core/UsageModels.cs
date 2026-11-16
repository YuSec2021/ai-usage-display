namespace AIUsage.Core;

public enum ProviderId { Codex, Claude, Kimi, MiniMax }
public enum SourceState { Ready, Waiting, Missing, IntegrationRequired, Stale, Unsupported, Failed }

public static class Providers
{
    public static readonly ProviderId[] All = Enum.GetValues<ProviderId>();
    public static string Name(this ProviderId id) => id switch
    {
        ProviderId.Codex => "Codex", ProviderId.Claude => "Claude Code",
        ProviderId.Kimi => "Kimi Code", _ => "MiniMax"
    };
    public static string Logo(this ProviderId id) => id switch
    {
        ProviderId.Codex => "chatgpt", ProviderId.Claude => "claude",
        ProviderId.Kimi => "kimi", _ => "minimax"
    };
    public static string Color(this ProviderId id) => id switch
    {
        ProviderId.Codex => "#33AD40", ProviderId.Claude => "#F56105",
        ProviderId.Kimi => "#3373F5", _ => "#F21A7A"
    };
}

public sealed record QuotaWindow(int Minutes, double Used, DateTimeOffset? ResetsAt, bool Unlimited = false)
{
    public bool IsCurrent(DateTimeOffset observed, DateTimeOffset now) =>
        double.IsFinite(Used) && now < ExpiresAt(observed);
    public DateTimeOffset ExpiresAt(DateTimeOffset observed)
    {
        var duration = TimeSpan.FromMinutes(Minutes > 0 ? Minutes : 15);
        var maximum = observed > DateTimeOffset.MaxValue - duration ? DateTimeOffset.MaxValue : observed + duration;
        return ResetsAt is { } reset && reset < maximum ? reset : maximum;
    }
    public double Fraction => Math.Clamp(Used / 100, 0, 1);
    public string Label => Minutes switch { 300 => "5 小时", 10080 => "7 天", > 0 => $"{Minutes} 分钟", _ => "额度窗口" };
}

public sealed record TokenUsage(long Input = 0, long Cached = 0, long Output = 0)
{
    // Cached input is a subset of Input, not an extra chargeable token count.
    public long Total => Add(Input, Output);
    public static long Add(long a, long b) => long.MaxValue - a < b ? long.MaxValue : a + b;
    public static TokenUsage operator +(TokenUsage a, TokenUsage b) =>
        new(Add(a.Input, b.Input), Add(a.Cached, b.Cached), Add(a.Output, b.Output));
    public TokenUsage Delta(TokenUsage old) =>
        new(Math.Max(0, Input - old.Input), Math.Max(0, Cached - old.Cached), Math.Max(0, Output - old.Output));
}

public sealed record DailyUsage(DateOnly Date, ProviderId Provider, TokenUsage Tokens);
public sealed record UsageSnapshot(ProviderId Provider, IReadOnlyList<QuotaWindow> Windows,
    DateTimeOffset ObservedAt, SourceState State, string Message, bool HistoryLimited = false)
{
    public QuotaWindow? FiveHour(DateTimeOffset now) => Windows.FirstOrDefault(
        window => window.Minutes == 300 && !window.Unlimited && window.IsCurrent(ObservedAt, now));
    public bool IsStale(DateTimeOffset now) => State == SourceState.Stale ||
        (Windows.Count > 0 && Windows.All(window => !window.IsCurrent(ObservedAt, now)));
    public string Status(DateTimeOffset now) => Windows.Count > 0 && Windows.All(window => !window.IsCurrent(ObservedAt, now))
        ? "上个周期已结束，等待更新" : State == SourceState.Stale ? Message + " · 上次有效数据" : Message;
    public static UsageSnapshot Empty(ProviderId provider, SourceState state, string message) =>
        new(provider, [], DateTimeOffset.MinValue, state, message);
}

public sealed record ProviderResult(UsageSnapshot Snapshot, IReadOnlyList<DailyUsage> History);
public interface IUsageProvider
{
    ProviderId Id { get; }
    Task<ProviderResult> LoadAsync(CancellationToken cancellationToken);
}

public readonly record struct WindowPlacement(int X, int Y, int Width, int Height)
{
    public WindowPlacement Fit(WindowPlacement work, int snap = 14)
    {
        var width = Math.Min(Math.Max(Width, 1), work.Width);
        var height = Math.Min(Math.Max(Height, 1), work.Height);
        var x = Math.Clamp(X, work.X, work.X + work.Width - width);
        var y = Math.Clamp(Y, work.Y, work.Y + work.Height - height);
        if (x - work.X < snap) x = work.X;
        if (work.X + work.Width - x - width < snap) x = work.X + work.Width - width;
        if (y - work.Y < snap) y = work.Y;
        if (work.Y + work.Height - y - height < snap) y = work.Y + work.Height - height;
        return new(x, y, width, height);
    }
}
