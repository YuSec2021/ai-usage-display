using AIUsage.Core;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using Windows.System;
using Windows.UI;

namespace AIUsage.Windows;

public sealed partial class FloatingWindow : Window, IDisposable
{
    private readonly App app;
    private readonly nint handle;
    private readonly WindowHook hook;
    private readonly FloatingDetailWindow detail;
    private readonly DispatcherTimer hideTimer;
    private bool moving;
    private bool pointerInDock;
    private bool pointerInDetail;
    private ProviderId? activeProvider;

    internal FloatingDetailWindow Detail => detail;

    public FloatingWindow(App app)
    {
        this.app = app;
        InitializeComponent();
        Title = "AI Usage Floating";
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
        AppWindow.Closing += (_, args) => { if (!app.Exiting) { args.Cancel = true; app.ShowFloating(false); } };
        AppWindow.Changed += (_, args) =>
        {
            if (args.DidVisibilityChange && !AppWindow.IsVisible)
                detail.HideDetail();
        };

        hideTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(180) };
        hideTimer.Tick += (_, _) =>
        {
            hideTimer.Stop();
            if (!pointerInDock && !pointerInDetail && !detail.IsPinned && !detail.IsMenuOpen)
                detail.HideDetail();
        };

        detail = new FloatingDetailWindow(
            app,
            onPointerEntered: () => { pointerInDetail = true; hideTimer.Stop(); },
            onPointerExited: () => { pointerInDetail = false; ScheduleDetailHide(); },
            onDismissRequested: () => detail.HideDetail(resetPin: true));

        surface.PointerPressed += (_, args) =>
        {
            if (args.Handled || !args.GetCurrentPoint(surface).Properties.IsLeftButtonPressed || IsInsideRing(args.OriginalSource)) return;
            if (!detail.IsPinned) detail.HideDetail();
            Native.ReleaseCapture();
            Native.SendMessageW(handle, 0x00A1, 2, 0);
            args.Handled = true;
        };
        surface.PointerEntered += (_, _) => { pointerInDock = true; hideTimer.Stop(); };
        surface.PointerExited += (_, _) => { pointerInDock = false; ScheduleDetailHide(); };
        surface.KeyDown += (_, args) =>
        {
            if (args.Key == VirtualKey.Escape)
            {
                detail.HideDetail(resetPin: true);
                args.Handled = true;
            }
        };
        surface.ActualThemeChanged += (_, _) =>
        {
            ApplySurfacePalette();
            Refresh();
        };

        hook = new(handle, (message, _, _) =>
        {
            if (message is 0x0232 or 0x007E or 0x02E0)
                DispatcherQueue.TryEnqueue(() => { if (!app.Exiting) FitAndRemember(); });
            return false;
        });

        ApplyAppearance();
        Refresh();
    }

    internal void ApplyAppearance()
    {
        surface.RequestedTheme = app.Preferences.Theme switch
        {
            "light" => ElementTheme.Light,
            "dark" => ElementTheme.Dark,
            _ => ElementTheme.Default
        };
        ((OverlappedPresenter)AppWindow.Presenter).IsAlwaysOnTop = app.Preferences.AlwaysOnTop;
        ApplySurfacePalette();
        detail.ApplyAppearance();
    }

    internal void Show()
    {
        Refresh();
        var work = Native.WorkArea(app.Preferences.FloatingX ?? 0, app.Preferences.FloatingY ?? 0, app.Preferences.FloatingDisplay).Bounds;
        var size = DesiredSize();
        var position = new WindowPlacement(
            app.Preferences.FloatingX ?? work.X + work.Width - size.Width - 24,
            app.Preferences.FloatingY ?? work.Y + work.Height - size.Height - 24,
            size.Width, size.Height).Fit(work);
        AppWindow.MoveAndResize(new RectInt32(position.X, position.Y, position.Width, position.Height));
        Activate();
    }

    internal void Hide()
    {
        hideTimer.Stop();
        detail.HideDetail(resetPin: true);
        AppWindow.Hide();
    }

    internal void ShowDetail(ProviderId provider, bool? pinned = null)
    {
        var snapshots = app.VisibleSnapshots();
        var index = -1;
        for (var i = 0; i < snapshots.Count; i++)
        {
            if (snapshots[i].Provider == provider) { index = i; break; }
        }
        if (index < 0) return;
        activeProvider = provider;
        var placement = ComputePopoverPlacement(snapshots.Count, index, out var scale);
        detail.ShowFor(snapshots[index], placement, scale, pinned);
    }

    private double Scale => Math.Max(Native.GetDpiForWindow(handle), 96) / 96d;

    private (int Width, int Height) DesiredSize()
    {
        var scale = Scale;
        var (width, height) = FloatingLayout.ComputeDockSize(app.VisibleSnapshots().Count);
        return ((int)Math.Round(width * scale), (int)Math.Round(height * scale));
    }

    private PopoverPlacement ComputePopoverPlacement(int count, int index, out double scale)
    {
        scale = Scale;
        var (dockDipWidth, _) = FloatingLayout.ComputeDockSize(count);
        Native.GetWindowRect(handle, out var rect);
        var dockWidth = Math.Max(rect.Right - rect.Left, (int)Math.Round(dockDipWidth * scale));
        var dockHeight = Math.Max(rect.Bottom - rect.Top, (int)Math.Round(FloatingLayout.DockHeight * scale));
        var dock = new WindowPlacement(rect.Left, rect.Top, dockWidth, dockHeight);
        var work = Native.WorkArea(dock.X, dock.Y, app.Preferences.FloatingDisplay).Bounds;
        var popoverWidth = (int)Math.Round(FloatingLayout.PopoverWidth * scale);
        var popoverHeight = (int)Math.Round(FloatingLayout.PopoverCardHeight * scale);
        var gap = (int)Math.Round(10 * scale);
        var ringCenterPx = FloatingLayout.RingCenterX(dockDipWidth, count, index) * scale;
        return FloatingLayout.PlacePopover(dock, work, popoverWidth, popoverHeight, gap, ringCenterPx, 22 * scale);
    }

    private bool IsInsideRing(object? source)
    {
        var current = source as DependencyObject;
        while (current is not null)
        {
            if (current == dockRow) return false;
            if (current is FrameworkElement element && dockRow.Children.Contains(element)) return true;
            current = VisualTreeHelper.GetParent(current);
        }
        return false;
    }

    private void ScheduleDetailHide()
    {
        if (detail.IsPinned || detail.IsMenuOpen) return;
        hideTimer.Stop();
        hideTimer.Start();
    }

    private void ApplySurfacePalette()
    {
        var dark = surface.ActualTheme == ElementTheme.Dark;
        surface.Background = new SolidColorBrush(dark
            ? Color.FromArgb(204, 28, 36, 50)
            : Color.FromArgb(199, 229, 237, 250));
        surface.BorderBrush = new SolidColorBrush(dark
            ? Color.FromArgb(44, 255, 255, 255)
            : Color.FromArgb(184, 255, 255, 255));
    }

    internal void Refresh()
    {
        var snapshots = app.VisibleSnapshots();
        var dark = surface.ActualTheme == ElementTheme.Dark;
        dockRow.Children.Clear();
        for (var i = 0; i < snapshots.Count; i++)
        {
            var snapshot = snapshots[i];
            var provider = snapshot.Provider;
            var ring = RingView.Create(snapshot, FloatingLayout.RingSize, () => ShowDetail(provider), dockStyle: true, darkTheme: dark);
            ring.PointerEntered += (_, _) =>
            {
                pointerInDock = true;
                hideTimer.Stop();
                ShowDetail(provider);
            };
            dockRow.Children.Add(ring);
        }
        ((OverlappedPresenter)AppWindow.Presenter).IsAlwaysOnTop = app.Preferences.AlwaysOnTop;
        var size = DesiredSize();
        AppWindow.Resize(new SizeInt32(size.Width, size.Height));

        if (detail.IsDetailVisible && activeProvider is { } current)
        {
            var index = -1;
            for (var i = 0; i < snapshots.Count; i++)
            {
                if (snapshots[i].Provider == current) { index = i; break; }
            }
            if (index >= 0)
            {
                detail.UpdateSnapshot(snapshots[index]);
                var placement = ComputePopoverPlacement(snapshots.Count, index, out var scale);
                detail.Reposition(placement, scale);
            }
            else
            {
                detail.HideDetail(resetPin: true);
            }
        }
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
                (int)(14 * Scale));
            AppWindow.MoveAndResize(new RectInt32(position.X, position.Y, position.Width, position.Height));
            app.Preferences.FloatingX = position.X;
            app.Preferences.FloatingY = position.Y;
            app.Preferences.FloatingDisplay = work.Device;
            app.Save();

            if (detail.IsDetailVisible && activeProvider is { } current)
            {
                var snapshots = app.VisibleSnapshots();
                for (var i = 0; i < snapshots.Count; i++)
                {
                    if (snapshots[i].Provider == current)
                    {
                        var placement = ComputePopoverPlacement(snapshots.Count, i, out var scale);
                        detail.Reposition(placement, scale);
                        break;
                    }
                }
            }
        }
        finally { moving = false; }
    }

    public void Dispose()
    {
        hideTimer.Stop();
        detail.Dispose();
        hook.Dispose();
        Close();
    }
}
