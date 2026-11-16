using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using AIUsage.Core;
using Microsoft.Win32;

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
    private readonly nint window;
    private readonly Action<ProviderId?> show;
    private readonly Action toggle, refresh, exit;
    private readonly WindowHook hook;
    private readonly Dictionary<ProviderId, nint> icons = [];
    private readonly Dictionary<ProviderId, Bitmap> logos = [];
    private readonly Dictionary<ProviderId, Guid> identifiers = [];
    private readonly uint taskbarCreated = Native.RegisterWindowMessageW("TaskbarCreated");
    private IReadOnlyList<UsageSnapshot> current = [];
    private readonly Func<bool> floatingVisible;
    public int Count => icons.Count;

    public TrayIcons(nint window, Action<ProviderId?> show, Action toggle, Action refresh, Action exit, Func<bool> floatingVisible, bool isolated = false)
    {
        this.window = window; this.show = show; this.toggle = toggle; this.refresh = refresh; this.exit = exit;
        this.floatingVisible = floatingVisible;
        foreach (var id in Providers.All)
        {
            logos[id] = new Bitmap(Path.Combine(AppContext.BaseDirectory, "Assets", id.Logo() + ".png"));
            identifiers[id] = isolated ? Guid.NewGuid() : new Guid($"67b4a8a0-4862-4cdc-9999-{((int)id + 1):D12}");
        }
        hook = new(window, Handle);
    }
    public void Update(IReadOnlyList<UsageSnapshot> snapshots)
    {
        current = snapshots;
        foreach (var id in icons.Keys.Except(snapshots.Select(snapshot => snapshot.Provider)).ToArray()) Remove(id);
        foreach (var snapshot in snapshots)
        {
            var icon = Draw(snapshot);
            var exists = icons.TryGetValue(snapshot.Provider, out var old);
            var data = Data(snapshot.Provider, icon, snapshot.Provider.Name() + " · " + snapshot.Status(DateTimeOffset.UtcNow));
            if (Shell_NotifyIconW(exists ? 1u : 0u, ref data))
            {
                icons[snapshot.Provider] = icon;
                if (old != 0) Native.DestroyIcon(old);
                if (!exists) { data.Version = 4; Shell_NotifyIconW(4, ref data); }
            }
            else Native.DestroyIcon(icon);
        }
    }
    private NotifyData Data(ProviderId id, nint icon = 0, string tip = "") => new()
    {
        Size = (uint)Marshal.SizeOf<NotifyData>(), Window = window, Id = (uint)id + 1,
        Flags = 1 | 2 | 4 | 0x20 | 0x80, Callback = CallbackMessage, Icon = icon,
        Guid = identifiers[id],
        Tip = tip.Length > 120 ? tip[..120] : tip, Info = "", InfoTitle = ""
    };
    private nint Draw(UsageSnapshot snapshot)
    {
        var size = (int)Math.Clamp(32 * Native.GetDpiForWindow(window) / 96, 32, 128);
        using var image = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(image);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        var dark = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 0) is int value && value == 0;
        var now = DateTimeOffset.UtcNow;
        var windowData = snapshot.FiveHour(now);
        var stale = snapshot.IsStale(now);
        var line = size * .08f;
        var bounds = new RectangleF(line, line, size - line * 2, size - line * 2);
        using var track = new Pen(Color.FromArgb(100, dark ? Color.White : Color.Black), line);
        if (windowData is null) track.DashStyle = DashStyle.Dash;
        graphics.DrawEllipse(track, bounds);
        if (windowData is { Fraction: > 0 })
        {
            var color = stale ? Color.Gray : windowData.Used >= 90 ? Color.FromArgb(232, 65, 65) :
                windowData.Used >= 75 ? Color.FromArgb(245, 160, 30) : ColorTranslator.FromHtml(snapshot.Provider.Color());
            using var progress = new Pen(color, line) { StartCap = LineCap.Round, EndCap = LineCap.Round };
            if (stale) progress.DashStyle = DashStyle.Dash;
            graphics.DrawArc(progress, bounds, -90, (float)(windowData.Fraction * 360));
        }
        var logoRect = new Rectangle((int)(size * .27), (int)(size * .27), (int)(size * .46), (int)(size * .46));
        if (dark && snapshot.Provider is ProviderId.Codex or ProviderId.Kimi)
        {
            using var attributes = new ImageAttributes();
            attributes.SetColorMatrix(new ColorMatrix(new[] { new float[] {-1,0,0,0,0}, new float[] {0,-1,0,0,0},
                new float[] {0,0,-1,0,0}, new float[] {0,0,0,1,0}, new float[] {1,1,1,0,1} }));
            graphics.DrawImage(logos[snapshot.Provider], logoRect, 0, 0, 128, 128, GraphicsUnit.Pixel, attributes);
        }
        else graphics.DrawImage(logos[snapshot.Provider], logoRect);
        return image.GetHicon();
    }
    private bool Handle(uint message, nuint wParam, nint lParam)
    {
        if (message == taskbarCreated)
        {
            foreach (var icon in icons.Values) Native.DestroyIcon(icon);
            icons.Clear(); Update(current); return false;
        }
        if (message == 0x031A || message == 0x001A) { Update(current); return false; }
        if (message != CallbackMessage) return false;
        var notification = (uint)((long)lParam & 0xffff);
        var identifier = (int)(((long)lParam >> 16) & 0xffff) - 1;
        if (notification is 0x0202 or 0x0400 or 0x0401) show(Enum.IsDefined(typeof(ProviderId), identifier) ? (ProviderId)identifier : null);
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
    private void Remove(ProviderId id)
    {
        var data = Data(id); Shell_NotifyIconW(2, ref data);
        if (icons.Remove(id, out var icon)) Native.DestroyIcon(icon);
    }
    public void Dispose()
    {
        foreach (var id in icons.Keys.ToArray()) Remove(id);
        hook.Dispose(); foreach (var logo in logos.Values) logo.Dispose();
    }
}
