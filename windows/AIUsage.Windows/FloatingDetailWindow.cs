using AIUsage.Core;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Media.Animation;
using System.Diagnostics;
using Windows.Foundation;
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
    private bool hiding;
    private Storyboard? motion, contentMotion;
    private readonly global::Windows.UI.ViewManagement.UISettings uiSettings = new();
    private readonly DispatcherTimer arrowTimer = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private readonly Stopwatch arrowClock = new();
    private PopoverPlacement? currentPlacement;
    private double currentScale = 1, arrowDip, arrowFrom, arrowTarget;

    internal bool IsPinned { get; private set; }
    internal bool IsMenuOpen => menuOpen;
    internal bool IsDetailVisible => Native.IsWindowVisible(handle);
    internal bool IsCaretAnimating => arrowTimer.IsEnabled;
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
        Native.ConfigureFloatingFrame(handle);
        AppWindow.Closing += (_, args) => { if (!app.Exiting) { args.Cancel = true; HideDetail(); } };

        root.PointerEntered += (_, _) =>
        {
            if (hiding)
            {
                hiding = false;
                AnimateDetail(closing: false);
            }
            this.onPointerEntered();
        };
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
        root.Loaded += (_, _) => { if (IsDetailVisible && !hiding) AnimateDetail(closing: false, fresh: true); };
        quotaTrack.SizeChanged += (_, _) => UpdateProgressWidth();
        arrowTimer.Tick += (_, _) =>
        {
            var t = Math.Clamp(arrowClock.Elapsed.TotalMilliseconds / 180, 0, 1);
            SetCaretPosition(arrowFrom + (arrowTarget - arrowFrom) * (1 - Math.Pow(1 - t, 3)));
            if (t >= 1) arrowTimer.Stop();
        };

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
        var visible = IsDetailVisible;
        var wasHiding = hiding;
        var changed = currentSnapshot?.Provider != snapshot.Provider;
        if (pinned is { } pinValue) IsPinned = pinValue;
        UpdateSnapshot(snapshot);
        Reposition(placement, scale);
        ((OverlappedPresenter)AppWindow.Presenter).IsAlwaysOnTop = app.Preferences.AlwaysOnTop;
        hiding = false;
        if (!visible || wasHiding)
        {
            if (!visible)
            {
                root.Opacity = 0;
                AppWindow.Show(false);
            }
            if (root.IsLoaded) AnimateDetail(closing: false, fresh: !visible);
        }
        else if (changed && uiSettings.AnimationsEnabled)
        {
            contentMotion?.Stop();
            contentMotion = new Storyboard();
            AddAnimation(contentMotion, cardContent, "Opacity", 0.3, 1, 150);
            var current = contentMotion;
            current.Completed += (_, _) => { cardContent.Opacity = 1; current.Stop(); };
            contentMotion.Begin();
        }
    }

    internal void UpdateSnapshot(UsageSnapshot snapshot)
    {
        currentSnapshot = snapshot;
        var now = DateTimeOffset.UtcNow;
        var quota = snapshot.FiveHour(now);
        var color = FloatingPresentation.RingColor(snapshot, now);
        providerTitle.Text = snapshot.Provider.Name();
        avatarIcon.UriSource = new Uri("ms-appx:///Assets/" + snapshot.Provider.Logo() + ".png");
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
        var sameWindow = currentPlacement is { } previous
            && previous.Bounds == placement.Bounds && previous.PlacedAbove == placement.PlacedAbove;
        var nextScale = Math.Max(scale, 0.5);
        var nextTarget = placement.ArrowOffsetPx / nextScale;
        if (IsDetailVisible && !hiding && sameWindow && arrowTimer.IsEnabled
            && Math.Abs(nextTarget - arrowTarget) <= 0.1 && Math.Abs(nextScale - currentScale) <= 0.001)
            return;
        var animateCaret = IsDetailVisible && !hiding && uiSettings.AnimationsEnabled && sameWindow;
        AppWindow.MoveAndResize(new RectInt32(placement.Bounds.X, placement.Bounds.Y, placement.Bounds.Width, placement.Bounds.Height));
        currentPlacement = placement;
        currentScale = nextScale;
        arrowTimer.Stop();
        card.Margin = placement.PlacedAbove ? new Thickness(0, 0, 0, FloatingLayout.CaretHeight) : new Thickness(0, FloatingLayout.CaretHeight, 0, 0);
        caretIndicator.VerticalAlignment = placement.PlacedAbove ? VerticalAlignment.Bottom : VerticalAlignment.Top;
        caretIndicator.Points = placement.PlacedAbove
            ? new PointCollection { new(0, 0), new(18, 0), new(9, 10) }
            : new PointCollection { new(0, 10), new(18, 10), new(9, 0) };
        root.RenderTransformOrigin = new Point(placement.ArrowOffsetPx / placement.Bounds.Width, placement.PlacedAbove ? 1 : 0);
        arrowTarget = nextTarget;
        if (animateCaret && Math.Abs(arrowTarget - arrowDip) > 0.1)
        {
            arrowFrom = arrowDip;
            arrowClock.Restart();
            arrowTimer.Start();
        }
        else SetCaretPosition(arrowTarget);
    }

    private void SetCaretPosition(double center)
    {
        arrowDip = center;
        caretIndicator.Margin = new Thickness(center - 9, 0, 0, 0);
        if (currentPlacement is not { } placement) return;
        Native.ApplyFloatingRegion(handle, placement.Bounds.Width, placement.Bounds.Height, 15 * currentScale,
            (int)Math.Round(FloatingLayout.CaretHeight * currentScale), center * currentScale, placement.PlacedAbove,
            (int)Math.Round(9 * currentScale));
    }

    internal void HideDetail(bool resetPin = false, bool immediate = false)
    {
        if (resetPin) IsPinned = false;
        UpdatePinAppearance();
        if (!IsDetailVisible) return;
        if (immediate || app.Exiting || !uiSettings.AnimationsEnabled)
        {
            motion?.Stop();
            arrowTimer.Stop();
            hiding = false;
            AppWindow.Hide();
        }
        else if (!hiding)
        {
            hiding = true;
            AnimateDetail(closing: true);
        }
    }

    private void AnimateDetail(bool closing, bool fresh = false)
    {
        var opacity = fresh ? 0 : root.Opacity;
        var offset = fresh ? (currentPlacement?.PlacedAbove == false ? -6 : 6) : detailTransform.TranslateY;
        var size = fresh ? .96 : detailTransform.ScaleX;
        motion?.Stop();
        contentMotion?.Stop();
        if (!uiSettings.AnimationsEnabled)
        {
            root.Opacity = 1;
            detailTransform.TranslateY = 0;
            detailTransform.ScaleX = detailTransform.ScaleY = 1;
            return;
        }
        var storyboard = new Storyboard();
        var duration = closing ? 140 : 180;
        AddAnimation(storyboard, root, "Opacity", opacity, closing ? 0 : 1, duration);
        AddAnimation(storyboard, detailTransform, "TranslateY", offset, closing ? (currentPlacement?.PlacedAbove == false ? -4 : 4) : 0, duration);
        AddAnimation(storyboard, detailTransform, "ScaleX", size, closing ? .98 : 1, duration);
        AddAnimation(storyboard, detailTransform, "ScaleY", size, closing ? .98 : 1, duration);
        storyboard.Completed += (_, _) =>
        {
            if (!ReferenceEquals(motion, storyboard)) return;
            if (hiding && ReferenceEquals(motion, storyboard))
            {
                arrowTimer.Stop();
                AppWindow.Hide();
                hiding = false;
            }
            root.Opacity = 1;
            detailTransform.TranslateY = 0;
            detailTransform.ScaleX = detailTransform.ScaleY = 1;
            storyboard.Stop();
        };
        motion = storyboard;
        storyboard.Begin();
    }

    private static void AddAnimation(Storyboard storyboard, DependencyObject target, string property, double from, double to, int duration)
    {
        var animation = new DoubleAnimation
        {
            From = from, To = to, Duration = new Duration(TimeSpan.FromMilliseconds(duration)),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(animation, target);
        Storyboard.SetTargetProperty(animation, property);
        storyboard.Children.Add(animation);
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
            ? Color.FromArgb(34, 158, 176, 200)
            : Color.FromArgb(31, 88, 112, 150));
        providerTitle.Foreground = new SolidColorBrush(dark
            ? Color.FromArgb(255, 238, 243, 250)
            : Color.FromArgb(255, 23, 35, 50));
        avatarIcon.Foreground = providerTitle.Foreground;
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
        caretIndicator.Fill = card.Background;
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

    public void Dispose()
    {
        arrowTimer.Stop();
        motion?.Stop();
        contentMotion?.Stop();
        Close();
    }
}
