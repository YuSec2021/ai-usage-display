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
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfoW(nint monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] internal static extern nint CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern bool AppendMenuW(nint menu, uint flags, nuint id, string? text);
    [DllImport("user32.dll")] internal static extern uint TrackPopupMenuEx(nint menu, uint flags, int x, int y, nint owner, nint parameters);
    [DllImport("user32.dll")] internal static extern bool DestroyMenu(nint menu);
    [DllImport("user32.dll")] internal static extern bool DestroyIcon(nint icon);

    internal static (WindowPlacement Bounds, string Device) WorkArea(int x, int y)
    {
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>(), Device = "" };
        if (!GetMonitorInfoW(MonitorFromPoint(new(x, y), 2), ref info))
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
