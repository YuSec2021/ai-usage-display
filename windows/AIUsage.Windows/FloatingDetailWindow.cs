using AIUsage.Core;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics;
using Windows.System;
using Windows.UI;

namespace AIUsage.Windows;

public sealed partial class FloatingDetailWindow : Window, IDisposable
{
    private readonly App app;
    private readonly nint handle;
    private readonly Action onPointerEntered;
    private readonly Action onPointerExited;
    private readonly Action onDismissRequested;
    private UsageSnapshot? currentSnapshot;
    private double currentFraction;
    private bool menuOpen;

    internal bool IsPinned { get; private set; }
    internal bool IsMenuOpen => menuOpen;
    internal bool IsDetailVisible => Native.IsWindowVisible(handle);
    internal ProviderId? ActiveProvider => currentSnapshot?.Provider;

    public FloatingDetailWindow(App app, Action onPointerEntered, Action onPointerExited, Action onDismissRequested)
    {
        this.app = app;
        this.onPointerEntered = onPointerEntered;
        this.onPointerExited = onPointerExited;
        this.onDismissRequested = onDismissRequested;
        InitializeComponent();
        Title = "AI Usage Detail";
        handle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        SystemBackdrop = new DesktopAcrylicBackdrop();
        var presenter = (OverlappedPresenter)AppWindow.Presenter;
        presenter.SetBorderAndTitleBar(false, false);
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        presenter.IsAlwaysOnTop = app.Preferences.AlwaysOnTop;
        AppWindow.IsShownInSwitchers = false;
        Native.ApplyRoundedCorners(handle);
        AppWindow.Closing += (_, args) => { if (!app.Exiting) { args.Cancel = true; HideDetail(); } };

        root.PointerEntered += (_, _) => this.onPointerEntered();
        root.PointerExited += (_, _) => this.onPointerExited();
        root.KeyDown += (_, args) =>
        {
            if (args.Key == VirtualKey.Escape)
            {
                this.onDismissRequested();
                args.Handled = true;
            }
        };
        root.ActualThemeChanged += (_, _) => ApplyThemePalette();
        quotaTrack.SizeChanged += (_, _) => UpdateProgressWidth();

        pinButton.Click += (_, _) =>
        {
            IsPinned = !IsPinned;
            UpdatePinAppearance();
        };

        var flyout = new MenuFlyout();
        var refreshItem = new MenuFlyoutItem { Text = "刷新额度" };
        refreshItem.Click += (_, _) => _ = app.Monitor.RefreshAsync();
        var mainItem = new MenuFlyoutItem { Text = "打开主面板" };
        mainItem.Click += (_, _) => app.ShowMain(currentSnapshot?.Provider);
        var hideItem = new MenuFlyoutItem { Text = "隐藏浮窗" };
        hideItem.Click += (_, _) => app.ShowFloating(false);
        flyout.Items.Add(refreshItem);
        flyout.Items.Add(mainItem);
        flyout.Items.Add(hideItem);
        flyout.Opened += (_, _) => { menuOpen = true; this.onPointerEntered(); };
        flyout.Closed += (_, _) => { menuOpen = false; this.onPointerExited(); };
        moreButton.Flyout = flyout;
        ToolTipService.SetToolTip(moreButton, "更多操作");
        AutomationProperties.SetName(moreButton, "更多操作");

        ApplyAppearance();
        AppWindow.Hide();
    }

    internal void ApplyAppearance()
    {
        root.RequestedTheme = app.Preferences.Theme switch
        {
            "light" => ElementTheme.Light,
            "dark" => ElementTheme.Dark,
            _ => ElementTheme.Default
        };
        ((OverlappedPresenter)AppWindow.Presenter).IsAlwaysOnTop = app.Preferences.AlwaysOnTop;
        ApplyThemePalette();
    }

    internal void ShowFor(UsageSnapshot snapshot, PopoverPlacement placement, double scale, bool? pinned = null)
    {
        if (pinned is { } pinValue) IsPinned = pinValue;
        UpdateSnapshot(snapshot);
        Reposition(placement, scale);
        ((OverlappedPresenter)AppWindow.Presenter).IsAlwaysOnTop = app.Preferences.AlwaysOnTop;
        if (!Native.IsWindowVisible(handle)) AppWindow.Show(false);
    }

    internal void UpdateSnapshot(UsageSnapshot snapshot)
    {
        currentSnapshot = snapshot;
        var now = DateTimeOffset.UtcNow;
        var quota = snapshot.FiveHour(now);
        var color = FloatingPresentation.RingColor(snapshot, now);
        providerTitle.Text = snapshot.Provider.Name();
        avatarIcon.Source = new BitmapImage(new Uri("ms-appx:///Assets/" + snapshot.Provider.Logo() + ".png"));
        avatarIcon.Opacity = quota is null ? 0.72 : 0.84;

        currentFraction = quota?.Fraction ?? 0;
        quotaTrack.Opacity = quota is null ? 0.55 : 1.0;
        quotaFill.Background = RingView.Brush(color);
        UpdateProgressWidth();

        resetLabel.Text = FloatingPresentation.FormatResetCountdown(snapshot, now);
        updatedLabel.Text = FloatingPresentation.FormatUpdatedAge(snapshot, now);
        AutomationProperties.SetName(card, $"{snapshot.Provider.Name()} 5 小时额度详情，{resetLabel.Text}，{updatedLabel.Text}");
        ApplyThemePalette();
    }

    internal void Reposition(PopoverPlacement placement, double scale)
    {
        AppWindow.MoveAndResize(new RectInt32(placement.Bounds.X, placement.Bounds.Y, placement.Bounds.Width, placement.Bounds.Height));
        var arrowDip = placement.ArrowOffsetPx / Math.Max(scale, 0.5);
        caretIndicator.VerticalAlignment = placement.PlacedAbove ? VerticalAlignment.Bottom : VerticalAlignment.Top;
        caretIndicator.Margin = placement.PlacedAbove
            ? new Thickness(Math.Max(14, arrowDip - 9), 0, 0, 2)
            : new Thickness(Math.Max(14, arrowDip - 9), 2, 0, 0);
    }

    internal void HideDetail(bool resetPin = false)
    {
        if (resetPin) IsPinned = false;
        UpdatePinAppearance();
        if (Native.IsWindowVisible(handle)) AppWindow.Hide();
    }

    private void UpdateProgressWidth()
    {
        var trackWidth = quotaTrack.ActualWidth > 0 ? quotaTrack.ActualWidth : FloatingLayout.PopoverWidth - 32;
        quotaFill.Width = currentFraction > 0 ? Math.Max(5, trackWidth * Math.Clamp(currentFraction, 0, 1)) : 0;
    }

    private bool IsDark => root.ActualTheme == ElementTheme.Dark;

    private void ApplyThemePalette()
    {
        var dark = IsDark;
        card.Background = new SolidColorBrush(dark
            ? Color.FromArgb(209, 28, 36, 50)
            : Color.FromArgb(199, 229, 237, 250));
        card.BorderBrush = new SolidColorBrush(dark
            ? Color.FromArgb(44, 255, 255, 255)
            : Color.FromArgb(184, 255, 255, 255));
        avatar.Background = new SolidColorBrush(dark
            ? Color.FromArgb(215, 232, 239, 249)
            : Color.FromArgb(31, 88, 112, 150));
        providerTitle.Foreground = new SolidColorBrush(dark
            ? Color.FromArgb(255, 238, 243, 250)
            : Color.FromArgb(255, 23, 35, 50));
        var muted = new SolidColorBrush(dark
            ? Color.FromArgb(255, 158, 176, 200)
            : Color.FromArgb(255, 100, 113, 135));
        subtitle.Foreground = muted;
        resetLabel.Foreground = muted;
        updatedLabel.Foreground = muted;
        moreIcon.Foreground = muted;
        quotaTrack.Background = new SolidColorBrush(dark
            ? Color.FromArgb(42, 255, 255, 255)
            : Color.FromArgb(44, 96, 117, 152));
        var accent = currentSnapshot is not null
            ? FloatingPresentation.RingColor(currentSnapshot, DateTimeOffset.UtcNow)
            : "#8B99AF";
        caretIndicator.Background = RingView.Brush(accent, dark ? (byte)190 : (byte)165);
        UpdatePinAppearance();
    }

    private void UpdatePinAppearance()
    {
        var dark = IsDark;
        pinIcon.Glyph = IsPinned ? "\uE77A" : "\uE718";
        ToolTipService.SetToolTip(pinButton, IsPinned ? "取消固定详情" : "固定详情");
        AutomationProperties.SetName(pinButton, IsPinned ? "取消固定详情" : "固定详情");
        if (IsPinned)
        {
            pinButton.Background = new SolidColorBrush(dark
                ? Color.FromArgb(56, 120, 168, 235)
                : Color.FromArgb(28, 63, 88, 127));
            pinIcon.Foreground = new SolidColorBrush(dark
                ? Color.FromArgb(255, 154, 197, 255)
                : Color.FromArgb(255, 46, 86, 138));
        }
        else
        {
            pinButton.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            pinIcon.Foreground = new SolidColorBrush(dark
                ? Color.FromArgb(255, 158, 176, 200)
                : Color.FromArgb(255, 100, 113, 135));
        }
    }

    public void Dispose() => Close();
}
