using AIUsage.Core;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;

namespace AIUsage.Windows;

internal sealed class FloatingWindow : Window, IDisposable
{
    private readonly App app;
    private readonly StackPanel content = new() { Spacing = 10, Margin = new Thickness(12, 8, 12, 8) };
    private readonly Border surface;
    private readonly nint handle;
    private readonly WindowHook hook;
    private bool moving;
    public FloatingWindow(App app)
    {
        this.app = app; Title = "AI Usage Floating";
        handle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        SystemBackdrop = new DesktopAcrylicBackdrop();
        surface = new Border { Child = content, CornerRadius = new CornerRadius(18), BorderThickness = new Thickness(1),
            BorderBrush = new SolidColorBrush(global::Windows.UI.Color.FromArgb(50, 128, 128, 128)) };
        Content = surface;
        var presenter = (OverlappedPresenter)AppWindow.Presenter;
        presenter.SetBorderAndTitleBar(false, false); presenter.IsResizable = false; presenter.IsMaximizable = false;
        presenter.IsMinimizable = false; presenter.IsAlwaysOnTop = app.Preferences.AlwaysOnTop;
        AppWindow.IsShownInSwitchers = false;
        AppWindow.Closing += (_, args) => { if (!app.Exiting) { args.Cancel = true; app.ShowFloating(false); } };
        hook = new(handle, (message, _, _) =>
        {
            if (message is 0x0232 or 0x007E or 0x02E0)
                DispatcherQueue.TryEnqueue(() => { if (!app.Exiting) FitAndRemember(); });
            return false;
        });
        ApplyAppearance(); Refresh();
    }
    internal void ApplyAppearance() => surface.RequestedTheme = app.Preferences.Theme switch
        { "light" => ElementTheme.Light, "dark" => ElementTheme.Dark, _ => ElementTheme.Default };
    internal void Show()
    {
        Refresh();
        var work = Native.WorkArea(app.Preferences.FloatingX ?? 0, app.Preferences.FloatingY ?? 0, app.Preferences.FloatingDisplay).Bounds;
        var size = DesiredSize();
        var position = new WindowPlacement(app.Preferences.FloatingX ?? work.X + work.Width - size.Width - 24,
            app.Preferences.FloatingY ?? work.Y + work.Height - size.Height - 24, size.Width, size.Height).Fit(work);
        AppWindow.MoveAndResize(new(position.X, position.Y, position.Width, position.Height));
        Activate();
    }
    private (int Width, int Height) DesiredSize()
    {
        var scale = Math.Max(Native.GetDpiForWindow(handle), 96) / 96d;
        var count = Math.Max(app.VisibleSnapshots().Count, 1);
        var width = app.Preferences.Expanded ? 310 : 116 + count * 44;
        var height = app.Preferences.Expanded ? 64 + count * 54 : 66;
        return ((int)(width * scale), (int)(height * scale));
    }
    internal void Refresh()
    {
        content.Children.Clear();
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        var drag = new TextBlock { Text = "⠿", FontSize = 20, Width = 20, VerticalAlignment = VerticalAlignment.Center };
        ToolTipService.SetToolTip(drag, "拖动浮窗，松开后吸附屏幕边缘");
        drag.PointerPressed += (_, args) =>
        {
            if (!args.GetCurrentPoint(drag).Properties.IsLeftButtonPressed) return;
            Native.ReleaseCapture(); Native.SendMessageW(handle, 0x00A1, 2, 0); args.Handled = true;
        };
        row.Children.Add(drag);
        if (app.Preferences.Expanded)
            row.Children.Add(new TextBlock { Text = app.SmokeOutput is null ? "AI Usage" : "AI Usage · 示例数据", FontSize = 14, Width = 168, VerticalAlignment = VerticalAlignment.Center });
        else foreach (var snapshot in app.VisibleSnapshots()) row.Children.Add(RingView.Create(snapshot, 35, () => app.ShowMain(snapshot.Provider)));
        var expand = new Button { Content = app.Preferences.Expanded ? "⌃" : "⌄", Padding = new Thickness(5), MinWidth = 24 };
        ToolTipService.SetToolTip(expand, app.Preferences.Expanded ? "收起浮窗" : "展开浮窗");
        expand.Click += (_, _) => { app.Preferences.Expanded = !app.Preferences.Expanded; app.Save(); Refresh(); FitAndRemember(); };
        row.Children.Add(expand);
        var hide = new Button { Content = "×", Padding = new Thickness(5), MinWidth = 24 };
        ToolTipService.SetToolTip(hide, "隐藏浮窗，可从托盘恢复");
        hide.Click += (_, _) => app.ShowFloating(false); row.Children.Add(hide); content.Children.Add(row);
        if (app.Preferences.Expanded)
            foreach (var snapshot in app.VisibleSnapshots())
            {
                var model = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
                model.Children.Add(RingView.Create(snapshot, 40, () => app.ShowMain(snapshot.Provider)));
                var labels = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center };
                labels.Children.Add(new TextBlock { Text = snapshot.Provider.Name(), FontSize = 13 });
                var quota = snapshot.FiveHour(DateTimeOffset.UtcNow);
                labels.Children.Add(new TextBlock { Text = quota?.ResetsAt is { } reset ? "重置于 " + reset.ToLocalTime().ToString("MM-dd HH:mm") : snapshot.Status(DateTimeOffset.UtcNow),
                    FontSize = 11, Opacity = .65, MaxWidth = 220, TextTrimming = TextTrimming.CharacterEllipsis });
                model.Children.Add(labels); content.Children.Add(model);
            }
        ((OverlappedPresenter)AppWindow.Presenter).IsAlwaysOnTop = app.Preferences.AlwaysOnTop;
        var size = DesiredSize(); AppWindow.Resize(new SizeInt32(size.Width, size.Height));
    }
    internal void FitAndRemember()
    {
        if (moving || !Native.IsWindowVisible(handle)) return;
        moving = true;
        try
        {
            Native.GetWindowRect(handle, out var rect);
            var work = Native.WorkArea(rect.Left, rect.Top);
            var size = DesiredSize();
            var position = new WindowPlacement(rect.Left, rect.Top, size.Width, size.Height).Fit(work.Bounds,
                (int)(14 * Math.Max(Native.GetDpiForWindow(handle), 96) / 96));
            AppWindow.MoveAndResize(new(position.X, position.Y, position.Width, position.Height));
            app.Preferences.FloatingX = position.X; app.Preferences.FloatingY = position.Y; app.Preferences.FloatingDisplay = work.Device;
            app.Save();
        }
        finally { moving = false; }
    }
    public void Dispose() { hook.Dispose(); Close(); }
}
