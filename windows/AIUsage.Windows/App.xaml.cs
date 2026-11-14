using AIUsage.Core;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace AIUsage.Windows;

public partial class App : Microsoft.UI.Xaml.Application
{
    internal Preferences Preferences { get; }
    internal ProviderPaths Paths { get; }
    internal UsageMonitor Monitor { get; }
    internal ClaudeIntegration Claude { get; }
    internal MainWindow Main { get; private set; } = null!;
    internal FloatingWindow Floating { get; private set; } = null!;
    internal bool Exiting { get; private set; }
    internal string? SmokeOutput { get; }
    internal string? SettingsWarning { get; private set; }
    private readonly bool canSave = true;
    private TrayIcons tray = null!;
    private readonly HttpClient http = new(new HttpClientHandler { AllowAutoRedirect = false });
    private readonly List<FileSystemWatcher> watchers = [];
    private DispatcherTimer? periodic, redraw, debounce;
    private readonly DispatcherQueue dispatcher;

    public App(string[] args)
    {
        InitializeComponent();
        dispatcher = DispatcherQueue.GetForCurrentThread();
        SmokeOutput = args.Length == 2 && args[0] == "--smoke-test" ? Path.GetFullPath(args[1]) : null;
        var data = SmokeOutput is not null ? Path.Combine(SmokeOutput, "isolated-data") :
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AIUsage");
        Paths = new(SmokeOutput is null ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) : Path.Combine(data, "home"), data);
        try { Preferences = AtomicJson.ReadPreferences(Path.Combine(data, "settings.json")); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        { Preferences = new(); canSave = false; SettingsWarning = "设置无法读取，本次使用默认配置且不覆盖原文件。"; }
        var claudeSettings = SmokeOutput is null ? Path.Combine(Paths.Claude, "settings.json") : Path.Combine(data, "claude-settings.json");
        Claude = new(claudeSettings, Path.Combine(data, "claude-collector.json"), Environment.ProcessPath!, Paths.ClaudeSnapshot);
        if (SmokeOutput is not null)
            Monitor = new(Providers.All.Select(id => (IUsageProvider)new FixtureProvider(id)).ToArray());
        else
        {
            var codex = new CodexClient(WindowsPaths.Codex);
            Monitor = new([
                new LogUsageProvider(ProviderId.Codex, Paths.Codex, liveReader: codex.ReadAsync),
                new LogUsageProvider(ProviderId.Claude, Paths.Claude, Paths.ClaudeSnapshot),
                new LogUsageProvider(ProviderId.Kimi, Paths.Kimi,
                    liveReader: token => KimiClient.ReadAsync(http, Credentials.Read(), token)),
                new LogUsageProvider(ProviderId.MiniMax, "")
            ], id => Preferences.Selected.Contains(id));
        }
        UnhandledException += (_, eventArgs) =>
        {
            if (SmokeOutput is not null)
                AtomicJson.Write(Path.Combine(SmokeOutput, "smoke-error.json"), new { error = eventArgs.Exception.ToString() });
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Main = new(this);
        Floating = new(this);
        tray = new(WinRT.Interop.WindowNative.GetWindowHandle(Main), ShowMain, () => ShowFloating(!Preferences.FloatingVisible),
            () => _ = Monitor.RefreshAsync(), Shutdown, () => Preferences.FloatingVisible, SmokeOutput is not null);
        Monitor.Changed += () => dispatcher.TryEnqueue(() => { if (!Exiting) Render(); });
        Main.Activate();
        if (Preferences.FloatingVisible) Floating.Show();
        periodic = new DispatcherTimer { Interval = TimeSpan.FromSeconds(Preferences.RefreshSeconds) };
        periodic.Tick += (_, _) => _ = Monitor.RefreshAsync();
        periodic.Start();
        redraw = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        redraw.Tick += (_, _) => Render(); redraw.Start();
        debounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(600) };
        debounce.Tick += (_, _) => { debounce.Stop(); _ = Monitor.RefreshAsync(); };
        if (SmokeOutput is null) WatchSources();
        Render();
        _ = Monitor.RefreshAsync();
        if (SmokeOutput is not null) _ = RunSmokeAsync();
    }

    internal IReadOnlyList<UsageSnapshot> VisibleSnapshots() => Preferences.VisibleProviders().Select(id =>
        Monitor.Snapshots.FirstOrDefault(snapshot => snapshot.Provider == id) ??
        UsageSnapshot.Empty(id, SourceState.Waiting, "等待数据")).ToArray();
    private void Render() { Main.Refresh(); Floating.Refresh(); tray.Update(VisibleSnapshots()); }
    internal void ShowMain(ProviderId? provider)
    {
        Main.SelectOverview(provider); Main.Activate();
        Native.SetForegroundWindow(WinRT.Interop.WindowNative.GetWindowHandle(Main));
    }
    internal void ShowFloating(bool visible)
    {
        Preferences.FloatingVisible = visible; Save();
        if (visible) Floating.Show(); else Floating.AppWindow.Hide();
        Main.RefreshSettingsStatus();
    }
    internal void Save()
    {
        if (canSave)
        {
            try { AtomicJson.Write(Path.Combine(Paths.Data, "settings.json"), Preferences); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            { SettingsWarning = "设置暂时无法保存，请检查本地目录权限。"; }
        }
        if (periodic is not null) periodic.Interval = TimeSpan.FromSeconds(Preferences.RefreshSeconds);
    }
    internal void ApplyAppearance() { Main.ApplyAppearance(); Floating.ApplyAppearance(); Floating.Refresh(); }
    internal void WatchSources()
    {
        foreach (var watcher in watchers) watcher.Dispose(); watchers.Clear();
        foreach (var directory in new[] { Paths.Codex, Paths.Claude, Paths.Kimi, Paths.Data }.Distinct().Where(Directory.Exists))
        {
            try
            {
                var watcher = new FileSystemWatcher(directory) { IncludeSubdirectories = true, NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size };
                void Request(string? path = null)
                {
                    if (path is not null && !path.EndsWith(".jsonl", StringComparison.OrdinalIgnoreCase) && path != Paths.ClaudeSnapshot) return;
                    dispatcher.TryEnqueue(() => { if (Exiting) return; debounce?.Stop(); debounce?.Start(); });
                }
                watcher.Changed += (_, args) => Request(args.FullPath); watcher.Created += (_, args) => Request(args.FullPath);
                watcher.Deleted += (_, args) => Request(args.FullPath); watcher.Renamed += (_, args) => Request(args.FullPath); watcher.Error += (_, _) => Request();
                watcher.EnableRaisingEvents = true; watchers.Add(watcher);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
    }
    internal void Shutdown()
    {
        if (Exiting) return; Exiting = true;
        periodic?.Stop(); redraw?.Stop(); debounce?.Stop();
        foreach (var watcher in watchers) watcher.Dispose();
        Monitor.Dispose(); tray.Dispose(); http.Dispose();
        Floating.Dispose(); Main.Close(); Exit();
    }
    private async Task RunSmokeAsync()
    {
        try
        {
            await Monitor.RefreshAsync();
            await Task.Delay(2500);
            Render();
            await SmokeCapture.RunAsync(this, tray.Count, SmokeOutput!);
            Shutdown();
        }
        catch (Exception error)
        {
            AtomicJson.Write(Path.Combine(SmokeOutput!, "smoke-error.json"), new { error = error.GetType().FullName, detail = error.Message });
            Environment.Exit(1);
        }
    }
    private sealed class FixtureProvider(ProviderId id) : IUsageProvider
    {
        public ProviderId Id => id;
        public Task<ProviderResult> LoadAsync(CancellationToken cancellationToken)
        {
            var now = DateTimeOffset.UtcNow;
            IReadOnlyList<QuotaWindow> windows = id == ProviderId.MiniMax ? [] :
                [new(300, id switch { ProviderId.Codex => 0, ProviderId.Claude => 82, _ => 37 }, now.AddHours(2)), new(10080, 40, now.AddDays(3))];
            return Task.FromResult(new ProviderResult(new(id, windows, now, SourceState.Ready, "CI 匿名示例数据"),
                Enumerable.Range(0, 7).Select(day => new DailyUsage(DateOnly.FromDateTime(now.LocalDateTime).AddDays(-day), id,
                    new TokenUsage((day + 1) * 1000, day * 100, 200))).ToArray()));
        }
    }
}
