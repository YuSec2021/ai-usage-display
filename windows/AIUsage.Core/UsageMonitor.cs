namespace AIUsage.Core;

public sealed class UsageMonitor(IReadOnlyList<IUsageProvider> providers, Func<ProviderId, bool>? enabled = null) : IDisposable
{
    private readonly object gate = new();
    private readonly CancellationTokenSource lifetime = new();
    private Task? current;
    private bool pending;
    private int generation;
    private readonly Dictionary<ProviderId, ProviderResult> results = providers.ToDictionary(provider => provider.Id,
        provider => new ProviderResult(UsageSnapshot.Empty(provider.Id, SourceState.Waiting, "等待首次刷新"), []));
    public event Action? Changed;
    public bool IsRefreshing { get; private set; }
    public DateTimeOffset? LastRefresh { get; private set; }
    public IReadOnlyList<UsageSnapshot> Snapshots { get { lock (gate) return results.Values.Select(result => result.Snapshot).ToArray(); } }
    public IReadOnlyList<DailyUsage> History { get { lock (gate) return results.Values.SelectMany(result => result.History).ToArray(); } }

    public Task RefreshAsync()
    {
        lock (gate)
        {
            if (lifetime.IsCancellationRequested) return Task.CompletedTask;
            pending = true;
            if (current is null || current.IsCompleted) current = Task.Run(DrainAsync);
            return current;
        }
    }
    public void Invalidate(ProviderId provider)
    {
        lock (gate)
        {
            generation++;
            results[provider] = new(UsageSnapshot.Empty(provider, SourceState.Waiting, "配置已变化，等待新数据"), []);
        }
        Changed?.Invoke();
        _ = RefreshAsync();
    }
    private async Task DrainAsync()
    {
        try
        {
            while (true)
            {
                int acceptedGeneration;
                lock (gate)
                {
                    if (!pending || lifetime.IsCancellationRequested) { current = null; return; }
                    pending = false; IsRefreshing = true; acceptedGeneration = generation;
                }
                Changed?.Invoke();
                var loaded = await Task.WhenAll(providers.Where(provider => enabled?.Invoke(provider.Id) ?? true).Select(async provider =>
                {
                    try { return await provider.LoadAsync(lifetime.Token); }
                    catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { throw; }
                    catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException)
                    {
                        lock (gate)
                        {
                            var old = results[provider.Id];
                            return old with { Snapshot = old.Snapshot with { State = SourceState.Stale, Message = "读取失败，等待下次刷新" } };
                        }
                    }
                }));
                lock (gate)
                {
                    if (!lifetime.IsCancellationRequested && generation == acceptedGeneration)
                    {
                        foreach (var result in loaded)
                        {
                            var snapshot = result.Snapshot;
                            var old = results[snapshot.Provider];
                            if (snapshot.Windows.Count == 0 && old.Snapshot.Windows.Count > 0 &&
                                snapshot.State != SourceState.Unsupported)
                                results[snapshot.Provider] = result with { Snapshot = old.Snapshot with
                                    { State = SourceState.Stale, Message = snapshot.Message, HistoryLimited = snapshot.HistoryLimited } };
                            else results[snapshot.Provider] = result;
                        }
                        LastRefresh = DateTimeOffset.UtcNow;
                    }
                    IsRefreshing = false;
                }
                Changed?.Invoke();
            }
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
        finally { lock (gate) IsRefreshing = false; }
    }
    public void Dispose() { lifetime.Cancel(); }
}
