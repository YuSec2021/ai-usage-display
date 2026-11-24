using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using AIUsage.Core;

namespace AIUsage.Windows;

internal sealed class TrayIcons : IDisposable
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyData
    {
        public uint Size; public nint Window; public uint Id, Flags, Callback; public nint Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State, StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint Version;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string InfoTitle;
        public uint InfoFlags; public Guid Guid; public nint BalloonIcon;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool Shell_NotifyIconW(uint operation, ref NotifyData data);
    private const uint CallbackMessage = 0x8000 + 42;
    private const uint TrayId = 1;
    private readonly nint window;
    private readonly Action<ProviderId?> show;
    private readonly Action toggle, refresh, exit;
    private readonly WindowHook hook;
    private readonly Guid identifier;
    private readonly uint taskbarCreated = Native.RegisterWindowMessageW("TaskbarCreated");
    private readonly Func<bool> floatingVisible;
    private IReadOnlyList<UsageSnapshot> current = [];
    private nint iconHandle;
    private bool registered;
    public int Count => registered ? 1 : 0;

    public TrayIcons(nint window, Action<ProviderId?> show, Action toggle, Action refresh, Action exit, Func<bool> floatingVisible, bool isolated = false)
    {
        this.window = window; this.show = show; this.toggle = toggle; this.refresh = refresh; this.exit = exit;
        this.floatingVisible = floatingVisible;
        identifier = isolated ? Guid.NewGuid() : new Guid("67b4a8a0-4862-4cdc-9999-000000000000");
        iconHandle = LoadAppIcon();
        hook = new(window, Handle);
    }

    public void Update(IReadOnlyList<UsageSnapshot> snapshots)
    {
        current = snapshots;
        var tip = snapshots.Count > 0 ? $"AI Usage · {snapshots.Count} 个模型监控中" : "AI Usage";
        if (iconHandle == 0) iconHandle = LoadAppIcon();
        var data = Data(iconHandle, tip);
        if (Shell_NotifyIconW(registered ? 1u : 0u, ref data))
        {
            if (!registered)
            {
                registered = true;
                data.Version = 4;
                Shell_NotifyIconW(4, ref data);
            }
        }
    }

    private NotifyData Data(nint icon = 0, string tip = "") => new()
    {
        Size = (uint)Marshal.SizeOf<NotifyData>(), Window = window, Id = TrayId,
        Flags = 1 | 2 | 4 | 0x20 | 0x80, Callback = CallbackMessage, Icon = icon,
        Guid = identifier,
        Tip = tip.Length > 120 ? tip[..120] : tip, Info = "", InfoTitle = ""
    };

    private nint LoadAppIcon()
    {
        var size = (int)Math.Clamp(32 * Native.GetDpiForWindow(window) / 96, 32, 128);
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico");
        try
        {
            if (File.Exists(path))
            {
                using var loaded = new Icon(path, new Size(size, size));
                using var bitmap = loaded.ToBitmap();
                return bitmap.GetHicon();
            }
        }
        catch { }

        using var fallback = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(fallback);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var line = Math.Max(2f, size * 0.12f);
        var bounds = new RectangleF(line, line, size - line * 2, size - line * 2);
        using var pen = new Pen(Color.FromArgb(255, 59, 130, 246), line);
        graphics.DrawEllipse(pen, bounds);
        return fallback.GetHicon();
    }

    private bool Handle(uint message, nuint wParam, nint lParam)
    {
        if (message == taskbarCreated)
        {
            registered = false;
            Update(current);
            return false;
        }
        if (message != CallbackMessage) return false;
        var notification = (uint)((long)lParam & 0xffff);
        if (notification is 0x0202 or 0x0400 or 0x0401) show(null);
        if (notification is 0x007B or 0x0205) Menu();
        return true;
    }

    private void Menu()
    {
        var menu = Native.CreatePopupMenu();
        try
        {
            Native.AppendMenuW(menu, 0, 1, "打开 AI Usage");
            Native.AppendMenuW(menu, 0, 2, floatingVisible() ? "隐藏浮窗" : "显示浮窗");
            Native.AppendMenuW(menu, 0, 3, "刷新用量");
            Native.AppendMenuW(menu, 0x800, 0, null);
            Native.AppendMenuW(menu, 0, 4, "退出");
            Native.GetCursorPos(out var point); Native.SetForegroundWindow(window);
            switch (Native.TrackPopupMenuEx(menu, 0x100 | 2, point.X, point.Y, window, 0))
            {
                case 1: show(null); break; case 2: toggle(); break; case 3: refresh(); break; case 4: exit(); break;
            }
        }
        finally { Native.DestroyMenu(menu); }
    }

    public void Dispose()
    {
        if (registered)
        {
            var data = Data();
            Shell_NotifyIconW(2, ref data);
            registered = false;
        }
        if (iconHandle != 0)
        {
            Native.DestroyIcon(iconHandle);
            iconHandle = 0;
        }
        hook.Dispose();
    }
}
