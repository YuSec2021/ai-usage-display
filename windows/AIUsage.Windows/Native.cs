using System.Runtime.InteropServices;
using AIUsage.Core;

namespace AIUsage.Windows;

internal static class Native
{
    [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X, Y; public Point(int x, int y) { X = x; Y = y; } }
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct MonitorInfo
    {
        public int Size; public Rect Monitor, Work; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] internal delegate nint WindowProcedure(nint window, uint message, nuint wParam, nint lParam);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] internal static extern nint SetWindowLongPtr(nint window, int index, nint value);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] internal static extern nint GetWindowLongPtr(nint window, int index);
    [DllImport("user32.dll")] internal static extern nint CallWindowProcW(nint previous, nint window, uint message, nuint wParam, nint lParam);
    [DllImport("user32.dll")] internal static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] internal static extern bool GetWindowRect(nint window, out Rect rect);
    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(nint window);
    [DllImport("user32.dll")] internal static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] internal static extern bool ReleaseCapture();
    [DllImport("user32.dll")] internal static extern nint SendMessageW(nint window, uint message, nuint wParam, nint lParam);
    [DllImport("user32.dll")] internal static extern bool SetForegroundWindow(nint window);
    [DllImport("user32.dll")] internal static extern bool ShowWindow(nint window, int command);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern nint FindWindowW(string? className, string title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern uint RegisterWindowMessageW(string name);
    [DllImport("user32.dll")] private static extern nint MonitorFromPoint(Point point, uint flags);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate bool MonitorCallback(nint monitor, nint context, ref Rect bounds, nint data);
    [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(nint context, nint clip, MonitorCallback callback, nint data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfoW(nint monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] internal static extern nint CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern bool AppendMenuW(nint menu, uint flags, nuint id, string? text);
    [DllImport("user32.dll")] internal static extern uint TrackPopupMenuEx(nint menu, uint flags, int x, int y, nint owner, nint parameters);
    [DllImport("user32.dll")] internal static extern bool DestroyMenu(nint menu);
    [DllImport("user32.dll")] internal static extern bool DestroyIcon(nint icon);
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(nint window, int attribute, ref int value, int size);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern int SetWindowRgn(nint window, nint region, bool redraw);
    [DllImport("user32.dll")] private static extern int GetWindowRgn(nint window, nint region);
    [DllImport("gdi32.dll")] private static extern nint CreateRoundRectRgn(int left, int top, int right, int bottom, int ellipseWidth, int ellipseHeight);
    [DllImport("gdi32.dll")] private static extern nint CreateRectRgn(int left, int top, int right, int bottom);
    [DllImport("gdi32.dll")] private static extern nint CreatePolygonRgn([In] Point[] points, int count, int mode);
    [DllImport("gdi32.dll")] private static extern int CombineRgn(nint destination, nint first, nint second, int mode);
    [DllImport("gdi32.dll")] private static extern bool PtInRegion(nint region, int x, int y);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(nint value);

    internal static bool MoveWindowPosition(nint window, int x, int y) =>
        SetWindowPos(window, 0, x, y, 0, 0, 0x0015); // SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE

    internal static void ConfigureFloatingFrame(nint window)
    {
        var style = GetWindowLongPtr(window, -16).ToInt64();
        SetWindowLongPtr(window, -16, (nint)(style & ~0x00C40000L)); // caption, border and resize frame
        var extended = GetWindowLongPtr(window, -20).ToInt64();
        SetWindowLongPtr(window, -20, (nint)(extended & ~0x00000301L)); // dialog/client/window edges
        _ = SetWindowPos(window, 0, 0, 0, 0, 0, 0x0037); // frame changed, no move/size/activation
        try
        {
            var preference = 1; // The explicit region supplies the full custom contour, including in VMs.
            _ = DwmSetWindowAttribute(window, 33, ref preference, sizeof(int));
            var borderNone = unchecked((int)0xFFFFFFFE); // DWMWA_COLOR_NONE
            _ = DwmSetWindowAttribute(window, 34, ref borderNone, sizeof(int));
        }
        catch { }
    }

    internal static bool ApplyFloatingRegion(nint window, int width, int height, double radius,
        int caretHeight = 0, double caretCenter = 0, bool placedAbove = true, int caretHalfWidth = 9)
    {
        var top = caretHeight > 0 && !placedAbove ? caretHeight : 0;
        var bottom = height - (caretHeight > 0 && placedAbove ? caretHeight : 0);
        var diameter = (int)Math.Round(radius * 2);
        var region = CreateRoundRectRgn(0, top, width + 1, bottom + 1, diameter, diameter);
        if (region == 0) return false;
        try
        {
            if (caretHeight > 0)
            {
                var center = (int)Math.Round(caretCenter);
                var baseY = placedAbove ? bottom - 1 : top + 1;
                var tipY = placedAbove ? height : 0;
                Point[] points = [new(center - caretHalfWidth, baseY), new(center, tipY), new(center + caretHalfWidth, baseY)];
                var caret = CreatePolygonRgn(points, points.Length, 1);
                if (caret == 0) return false;
                try { if (CombineRgn(region, region, caret, 2) == 0) return false; } // RGN_OR
                finally { DeleteObject(caret); }
            }
            if (SetWindowRgn(window, region, true) == 0) return false;
            region = 0; // Success transfers HRGN ownership to Windows.
            return true;
        }
        finally { if (region != 0) DeleteObject(region); }
    }

    internal static bool WindowRegionContains(nint window, int x, int y)
    {
        var region = CreateRectRgn(0, 0, 0, 0);
        if (region == 0) return false;
        try { return GetWindowRgn(window, region) > 0 && PtInRegion(region, x, y); }
        finally { DeleteObject(region); }
    }

    internal static (WindowPlacement Bounds, string Device) WorkArea(int x, int y, string? preferredDevice = null)
    {
        var monitor = MonitorFromPoint(new(x, y), 2);
        if (!string.IsNullOrEmpty(preferredDevice))
        {
            EnumDisplayMonitors(0, 0, (nint candidate, nint context, ref Rect bounds, nint data) =>
            {
                var candidateInfo = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>(), Device = "" };
                if (!GetMonitorInfoW(candidate, ref candidateInfo) || candidateInfo.Device != preferredDevice) return true;
                monitor = candidate; return false;
            }, 0);
        }
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>(), Device = "" };
        if (!GetMonitorInfoW(monitor, ref info))
            return (new(0, 0, 1280, 720), "");
        return (new(info.Work.Left, info.Work.Top, info.Work.Right - info.Work.Left, info.Work.Bottom - info.Work.Top), info.Device);
    }
}

internal sealed class WindowHook : IDisposable
{
    private readonly nint window;
    private readonly Native.WindowProcedure callback;
    private nint original;
    public WindowHook(nint window, Func<uint, nuint, nint, bool> handler)
    {
        this.window = window;
        callback = (handle, message, wParam, lParam) =>
            handler(message, wParam, lParam) ? 0 : Native.CallWindowProcW(original, handle, message, wParam, lParam);
        original = Native.SetWindowLongPtr(window, -4, Marshal.GetFunctionPointerForDelegate(callback));
        if (original == 0) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    public void Dispose()
    {
        if (original != 0) { Native.SetWindowLongPtr(window, -4, original); original = 0; }
        GC.KeepAlive(callback);
    }
}
