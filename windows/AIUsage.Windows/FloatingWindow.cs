using AIUsage.Core;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
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
    private bool pointerTracking;
    private bool dragging;
    private bool suppressRingTap;
    private bool pendingRefresh;
    private uint dragPointerId;
    private Native.Point dragStartCursor;
    private int dragStartWindowX;
    private int dragStartWindowY;
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
        Native.ConfigureFloatingFrame(handle);
        AppWindow.Closing += (_, args) => { if (!app.Exiting) { args.Cancel = true; app.ShowFloating(false); } };
        AppWindow.Changed += (_, args) =>
        {
            if (args.DidVisibilityChange && !AppWindow.IsVisible && detail is { } panel)
                panel.HideDetail(immediate: true);
        };

        hideTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(180) };
        hideTimer.Tick += (_, _) =>
        {
            hideTimer.Stop();
            if (!pointerInDock && !pointerInDetail && detail is { } panel && !panel.IsPinned && !panel.IsMenuOpen)
                panel.HideDetail();
        };

        detail = new FloatingDetailWindow(
            app,
            onPointerEntered: () => { pointerInDetail = true; hideTimer.Stop(); },
            onPointerExited: () => { pointerInDetail = false; ScheduleDetailHide(); },
            onDismissRequested: () => detail?.HideDetail(resetPin: true));

        surface.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(OnSurfacePointerPressed), true);
        surface.AddHandler(UIElement.PointerMovedEvent, new PointerEventHandler(OnSurfacePointerMoved), true);
        surface.AddHandler(UIElement.PointerReleasedEvent, new PointerEventHandler(OnSurfacePointerReleased), true);
        surface.PointerCanceled += (_, args) => EndDrag(args.Pointer, commit: false);
        surface.PointerCaptureLost += (_, args) => EndDrag(args.Pointer, commit: true);
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
        detail.HideDetail(resetPin: true, immediate: true);
        AppWindow.Hide();
    }

    internal void ShowDetail(ProviderId provider, bool? pinned = null)
    {
        if (detail.IsPinned && pinned is null && detail.ActiveProvider != provider) return;
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
        var popoverHeight = (int)Math.Round(FloatingLayout.PopoverHeight * scale);
        var gap = (int)Math.Round(FloatingLayout.PopoverGap * scale);
        var ringCenterPx = FloatingLayout.RingCenterX(dockDipWidth, count, index) * scale;
        return FloatingLayout.PlacePopover(dock, work, popoverWidth, popoverHeight, gap, ringCenterPx, 22 * scale);
    }

    private void OnSurfacePointerPressed(object sender, PointerRoutedEventArgs args)
    {
        if (!args.GetCurrentPoint(surface).Properties.IsLeftButtonPressed) return;
        if (!Native.GetCursorPos(out dragStartCursor) || !Native.GetWindowRect(handle, out var rect)) return;
        dragStartWindowX = rect.Left;
        dragStartWindowY = rect.Top;
        dragPointerId = args.Pointer.PointerId;
        pointerTracking = true;
        dragging = false;
        suppressRingTap = false;
        surface.CapturePointer(args.Pointer);
    }

    private void OnSurfacePointerMoved(object sender, PointerRoutedEventArgs args)
    {
        if (!pointerTracking || args.Pointer.PointerId != dragPointerId) return;
        if (!args.GetCurrentPoint(surface).Properties.IsLeftButtonPressed)
        {
            EndDrag(args.Pointer, commit: dragging);
            return;
        }
        if (!Native.GetCursorPos(out var cursor)) return;
        var dx = cursor.X - dragStartCursor.X;
        var dy = cursor.Y - dragStartCursor.Y;
        if (!dragging)
        {
            if (!FloatingLayout.ShouldStartDrag(dx, dy, Scale)) return;
            dragging = true;
            suppressRingTap = true;
            hideTimer.Stop();
            if (!detail.IsPinned) detail.HideDetail(immediate: true);
        }
        Native.MoveWindowPosition(handle, dragStartWindowX + dx, dragStartWindowY + dy);
        args.Handled = true;
    }

    private void OnSurfacePointerReleased(object sender, PointerRoutedEventArgs args)
    {
        if (!pointerTracking || args.Pointer.PointerId != dragPointerId) return;
        var wasDragging = dragging;
        EndDrag(args.Pointer, commit: wasDragging);
        if (wasDragging) args.Handled = true;
    }

    private void EndDrag(Pointer pointer, bool commit)
    {
        if (!pointerTracking || pointer.PointerId != dragPointerId) return;
        var wasDragging = dragging;
        pointerTracking = false;
        dragging = false;
        surface.ReleasePointerCapture(pointer);
        if (wasDragging && commit) FitAndRemember();
        if (pendingRefresh)
        {
            pendingRefresh = false;
            Refresh();
        }
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
        if (dragging)
        {
            pendingRefresh = true;
            return;
        }
        var snapshots = app.VisibleSnapshots();
        var dark = surface.ActualTheme == ElementTheme.Dark;
        dockRow.Children.Clear();
        for (var i = 0; i < snapshots.Count; i++)
        {
            var snapshot = snapshots[i];
            var provider = snapshot.Provider;
            var ring = RingView.Create(snapshot, FloatingLayout.RingSize, () =>
            {
                if (suppressRingTap) { suppressRingTap = false; return; }
                ShowDetail(provider, pinned: false);
            }, dockStyle: true, darkTheme: dark);
            ring.PointerEntered += (_, _) =>
            {
                if (dragging) return;
                pointerInDock = true;
                hideTimer.Stop();
                ShowDetail(provider);
            };
            dockRow.Children.Add(ring);
        }
        ((OverlappedPresenter)AppWindow.Presenter).IsAlwaysOnTop = app.Preferences.AlwaysOnTop;
        var size = DesiredSize();
        AppWindow.Resize(new SizeInt32(size.Width, size.Height));
        Native.ApplyFloatingRegion(handle, size.Width, size.Height, 29 * Scale);

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
            Native.ApplyFloatingRegion(handle, size.Width, size.Height, 29 * Scale);
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
