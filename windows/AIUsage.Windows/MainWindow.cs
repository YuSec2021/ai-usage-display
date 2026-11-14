using System.Globalization;
using AIUsage.Core;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace AIUsage.Windows;

internal sealed class MainWindow : Window
{
    private readonly App app;
    private readonly NavigationView navigation;
    private readonly Grid root = new();
    private readonly TextBlock status = new() { FontSize = 12, Opacity = .7, TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock settingsStatus = new() { FontSize = 12, TextWrapping = TextWrapping.Wrap };
    private string page = "overview";
    private ProviderId? focused;
    public MainWindow(App app)
    {
        this.app = app; Title = "AI Usage"; SystemBackdrop = new MicaBackdrop();
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        navigation = new NavigationView { PaneDisplayMode = NavigationViewPaneDisplayMode.Top,
            IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed, IsSettingsVisible = false,
            Header = new TextBlock { Text = app.SmokeOutput is null ? "AI Usage" : "AI Usage · CI 匿名示例", FontSize = 26, FontWeight = FontWeights.SemiBold } };
        foreach (var (tag, text, icon) in new[] { ("overview", "用量", Symbol.ViewAll), ("history", "历史", Symbol.Calendar), ("settings", "设置", Symbol.Setting) })
            navigation.MenuItems.Add(new NavigationViewItem { Content = text, Tag = tag, Icon = new SymbolIcon(icon) });
        navigation.SelectionChanged += (_, args) =>
        {
            if (args.SelectedItem is NavigationViewItem item) { page = (string)item.Tag; Build(); }
        };
        root.Children.Add(navigation); Content = root;
        AppWindow.Resize(new(480, 760));
        AppWindow.Closing += (_, args) => { if (!app.Exiting) { args.Cancel = true; AppWindow.Hide(); } };
        ApplyAppearance(); navigation.SelectedItem = navigation.MenuItems[0];
    }
    internal void ApplyAppearance() => root.RequestedTheme = app.Preferences.Theme switch
        { "light" => ElementTheme.Light, "dark" => ElementTheme.Dark, _ => ElementTheme.Default };
    internal void SelectOverview(ProviderId? provider)
    { focused = provider; navigation.SelectedItem = navigation.MenuItems[0]; page = "overview"; Build(); }
    internal void Refresh()
    {
        status.Text = app.SettingsWarning ?? (app.Monitor.IsRefreshing ? "正在刷新…" :
            app.Monitor.LastRefresh is { } date ? "更新于 " + date.ToLocalTime().ToString("HH:mm:ss") : "等待首次数据");
        if (page != "settings") Build(); else RefreshSettingsStatus();
    }
    private void Build()
    {
        if (status.Parent is Panel previous) previous.Children.Remove(status);
        var content = new StackPanel { Spacing = 14, Margin = new Thickness(22, 10, 22, 24) };
        content.Children.Add(status);
        if (page == "overview") Overview(content);
        else if (page == "history") History(content);
        else Settings(content);
        navigation.Content = new ScrollViewer { Content = content, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    }
    private void Overview(StackPanel content)
    {
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        actions.Children.Add(Button("刷新", () => _ = app.Monitor.RefreshAsync()));
        actions.Children.Add(Button(app.Preferences.FloatingVisible ? "隐藏浮窗" : "显示浮窗", () => app.ShowFloating(!app.Preferences.FloatingVisible)));
        content.Children.Add(actions);
        if (app.VisibleSnapshots().Count == 0) content.Children.Add(Label("尚未选择模型，请在设置中启用。"));
        foreach (var snapshot in app.VisibleSnapshots().OrderBy(snapshot => snapshot.Provider == focused ? 0 : 1))
        {
            var body = new StackPanel { Spacing = 8 };
            var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14 };
            header.Children.Add(RingView.Create(snapshot, 62));
            var title = new StackPanel { Spacing = 5, VerticalAlignment = VerticalAlignment.Center };
            title.Children.Add(new TextBlock { Text = snapshot.Provider.Name(), FontSize = 17, FontWeight = FontWeights.SemiBold });
            title.Children.Add(Label(snapshot.FiveHour(DateTimeOffset.UtcNow)?.ResetsAt is { } reset
                ? "5 小时窗口 · 重置于 " + reset.ToLocalTime().ToString("MM-dd HH:mm") : "5 小时额度尚无有效数据", 12));
            header.Children.Add(title); body.Children.Add(header);
            body.Children.Add(Label(snapshot.Status(DateTimeOffset.UtcNow), 12));
            foreach (var window in snapshot.Windows.Where(window => window.Minutes != 300))
            {
                var current = window.IsCurrent(snapshot.ObservedAt, DateTimeOffset.UtcNow);
                var text = window.Unlimited ? "无限制" : !current ? "已过期，等待更新" : "额度数据有效";
                if (window.ResetsAt is { } next) text += " · 重置于 " + next.ToLocalTime().ToString("MM-dd HH:mm");
                body.Children.Add(Label(window.Label + " · " + text, 12));
                if (!window.Unlimited && current)
                    body.Children.Add(new ProgressBar { Minimum = 0, Maximum = 1, Value = window.Fraction });
            }
            var today = app.Monitor.History.Where(day => day.Provider == snapshot.Provider && day.Date == DateOnly.FromDateTime(DateTime.Now))
                .Aggregate(new TokenUsage(), (sum, day) => sum + day.Tokens);
            if (app.Monitor.History.Any(day => day.Provider == snapshot.Provider)) body.Children.Add(Label("今日 Token · " + FormatTokens(today.Total), 13));
            if (snapshot.HistoryLimited) body.Children.Add(Label("日志初读范围有限，Token 历史可能不完整。", 11));
            content.Children.Add(Card(body));
        }
        content.Children.Add(Label("主圆环仅表示 5 小时已用额度；虚线代表未知。关闭面板后仍可从托盘恢复。", 11));
    }
    private void History(StackPanel content)
    {
        content.Children.Add(Label("最近 7 天 · 本地 Token", 18));
        foreach (var provider in app.Preferences.VisibleProviders().Where(id => id != ProviderId.MiniMax))
        {
            var body = new StackPanel { Spacing = 10 };
            body.Children.Add(Label(provider.Name(), 16));
            var history = app.Monitor.History.Where(day => day.Provider == provider).GroupBy(day => day.Date)
                .ToDictionary(group => group.Key, group => group.Aggregate(new TokenUsage(), (sum, day) => sum + day.Tokens).Total);
            if (history.Count == 0) body.Children.Add(Label("尚无可读取的本地 Token 数据。", 12));
            else
            {
                var bars = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
                var maximum = Math.Max(history.Values.Max(), 1);
                for (var index = -6; index <= 0; index++)
                {
                    var date = DateOnly.FromDateTime(DateTime.Now).AddDays(index);
                    var tokens = history.GetValueOrDefault(date);
                    var column = new StackPanel { Width = 36, Spacing = 6 };
                    var area = new Grid { Height = 110 };
                    area.Children.Add(new Border { Height = Math.Max(2, tokens / (double)maximum * 100), VerticalAlignment = VerticalAlignment.Bottom,
                        Background = RingView.Brush(provider.Color()), CornerRadius = new CornerRadius(3) });
                    ToolTipService.SetToolTip(area, tokens.ToString("N0", CultureInfo.CurrentCulture) + " Token");
                    column.Children.Add(area); column.Children.Add(Label(date.ToString("MM-dd"), 10)); bars.Children.Add(column);
                }
                body.Children.Add(bars);
                body.Children.Add(Label("7 天合计 · " + FormatTokens(history.Values.Aggregate(0L, TokenUsage.Add)), 12));
                if (app.Monitor.Snapshots.FirstOrDefault(snapshot => snapshot.Provider == provider)?.HistoryLimited == true)
                    body.Children.Add(Label("仅统计可读取日志范围，不代表完整账单。", 11));
            }
            content.Children.Add(Card(body));
        }
    }
    private void Settings(StackPanel content)
    {
        if (settingsStatus.Parent is Panel old) old.Children.Remove(settingsStatus);
        content.Children.Add(settingsStatus); RefreshSettingsStatus();
        var display = new StackPanel { Spacing = 12 };
        display.Children.Add(Label("显示与外观", 18));
        var theme = new ComboBox { Header = "主题", HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var (label, value) in new[] { ("跟随系统", "system"), ("浅色", "light"), ("深色", "dark") })
            theme.Items.Add(new ComboBoxItem { Content = label, Tag = value });
        theme.SelectedIndex = app.Preferences.Theme switch { "light" => 1, "dark" => 2, _ => 0 };
        theme.SelectionChanged += (_, _) => { app.Preferences.Theme = (string)((ComboBoxItem)theme.SelectedItem).Tag; app.Save(); app.ApplyAppearance(); };
        display.Children.Add(theme);
        var visible = new ToggleSwitch { Header = "桌面浮窗", IsOn = app.Preferences.FloatingVisible };
        visible.Toggled += (_, _) => app.ShowFloating(visible.IsOn); display.Children.Add(visible);
        var top = new ToggleSwitch { Header = "浮窗始终置顶", IsOn = app.Preferences.AlwaysOnTop };
        top.Toggled += (_, _) => { app.Preferences.AlwaysOnTop = top.IsOn; app.Save(); app.Floating.Refresh(); }; display.Children.Add(top);
        var interval = new ComboBox { Header = "后台刷新间隔", HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var seconds in new[] { 15, 30, 60, 300 }) interval.Items.Add(seconds);
        interval.SelectedItem = app.Preferences.RefreshSeconds;
        interval.SelectionChanged += (_, _) => { if (interval.SelectedItem is int seconds) { app.Preferences.RefreshSeconds = seconds; app.Save(); } };
        display.Children.Add(interval); content.Children.Add(Card(display));

        var models = new StackPanel { Spacing = 12 }; models.Children.Add(Label("模型与顺序", 18));
        foreach (var id in app.Preferences.Order)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var selected = new CheckBox { Content = id.Name(), IsChecked = app.Preferences.Selected.Contains(id), Width = 200 };
            void Change()
            {
                var ids = app.Preferences.Selected.ToHashSet(); if (selected.IsChecked == true) ids.Add(id); else ids.Remove(id);
                app.Preferences.Selected = ids.ToArray(); app.Save(); app.Monitor.Invalidate(id); app.Floating.Refresh();
            }
            selected.Checked += (_, _) => Change(); selected.Unchecked += (_, _) => Change(); row.Children.Add(selected);
            row.Children.Add(Button("↑", () => Move(id, -1))); row.Children.Add(Button("↓", () => Move(id, 1))); models.Children.Add(row);
        }
        models.Children.Add(Label("托盘图标的最终排列与折叠由 Windows 控制；浮窗按这里的顺序显示。", 11));
        content.Children.Add(Card(models));

        var integration = new StackPanel { Spacing = 10 }; integration.Children.Add(Label("Claude Code 集成", 18));
        integration.Children.Add(Label("通过官方 status line 获取额度。安装会备份原命令，卸载仅在配置仍属于本集成时恢复。", 12));
        integration.Children.Add(Button(app.Claude.IsInstalled() ? "卸载并恢复原配置" : "安装用量集成", () =>
        {
            TryAction(() =>
            {
                if (app.Claude.IsInstalled())
                {
                    if (!app.Claude.Uninstall()) throw new InvalidOperationException("Claude 配置已被外部修改，未覆盖当前命令。");
                }
                else app.Claude.Install();
                app.WatchSources(); app.Monitor.Invalidate(ProviderId.Claude);
            });
            Build();
        })); content.Children.Add(Card(integration));

        var kimi = new StackPanel { Spacing = 10 }; kimi.Children.Add(Label("Kimi Code 授权", 18));
        kimi.Children.Add(Label("Key 仅存入当前用户的 Windows 凭证管理器，直接请求 Kimi 官方额度接口。", 12));
        if (!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("KIMI_API_KEY")))
            kimi.Children.Add(Label("当前环境变量 KIMI_API_KEY 优先；保存或移除本地 Key 不会修改此环境变量。", 12));
        var key = new PasswordBox { PlaceholderText = "Kimi Code API Key" }; kimi.Children.Add(key);
        var keyActions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        keyActions.Children.Add(Button("保存", () => TryAction(() =>
        { Credentials.Save(key.Password); key.Password = ""; app.Monitor.Invalidate(ProviderId.Kimi); })));
        keyActions.Children.Add(Button("移除", () => TryAction(() =>
        { Credentials.Remove(); key.Password = ""; app.Monitor.Invalidate(ProviderId.Kimi); })));
        kimi.Children.Add(keyActions); content.Children.Add(Card(kimi));
        content.Children.Add(Label("MiniMax Windows 缓存尚未验证，首版暂不支持。WSL 尚未接入。凭证不会保存到设置 JSON 或诊断日志。", 12));
        content.Children.Add(Button("退出 AI Usage", app.Shutdown));
    }
    private void Move(ProviderId id, int offset)
    {
        var order = app.Preferences.Order.ToList(); var index = order.IndexOf(id); var target = Math.Clamp(index + offset, 0, order.Count - 1);
        (order[index], order[target]) = (order[target], order[index]); app.Preferences.Order = order.ToArray(); app.Save(); app.Floating.Refresh(); Build();
    }
    internal void RefreshSettingsStatus()
    {
        if (settingsStatus.Text.StartsWith("操作失败")) return;
        settingsStatus.Text = "Claude 集成：" + (app.Claude.IsInstalled() ? "已安装" : "未安装") + " · Kimi Key：" +
            (app.SmokeOutput is not null ? "隔离验证，不读取凭证" : Credentials.Read() is null ? "未配置" : "已配置，额度结果见用量页");
    }
    private void TryAction(Action action)
    {
        try { action(); settingsStatus.Text = "操作已完成"; RefreshSettingsStatus(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or InvalidOperationException or System.ComponentModel.Win32Exception)
        { settingsStatus.Text = "操作失败：" + (error is InvalidOperationException ? error.Message : "请检查文件权限、配置格式或 Windows 凭证服务。"); }
    }
    private static Button Button(string text, Action action)
    { var button = new Button { Content = text }; button.Click += (_, _) => action(); return button; }
    private static TextBlock Label(string text, double size = 13) => new() { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap };
    private static Border Card(UIElement body) => new() { Child = body, Padding = new Thickness(16), CornerRadius = new CornerRadius(14),
        Background = new SolidColorBrush(Color.FromArgb(18, 128, 128, 128)), BorderBrush = new SolidColorBrush(Color.FromArgb(30, 128, 128, 128)), BorderThickness = new Thickness(1) };
    private static string FormatTokens(long tokens) => tokens >= 1_000_000 ? (tokens / 1_000_000d).ToString("0.0", CultureInfo.CurrentCulture) + "M" :
        tokens >= 1000 ? (tokens / 1000d).ToString("0.0", CultureInfo.CurrentCulture) + "K" : tokens.ToString(CultureInfo.CurrentCulture);
}
