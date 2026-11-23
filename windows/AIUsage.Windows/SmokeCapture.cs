using AIUsage.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace AIUsage.Windows;

internal static class SmokeCapture
{
    public static async Task RunAsync(App app, int trayCount, string output)
    {
        Directory.CreateDirectory(output);
        var main = WinRT.Interop.WindowNative.GetWindowHandle(app.Main);
        var floating = WinRT.Interop.WindowNative.GetWindowHandle(app.Floating);
        var topmost = ((long)Native.GetWindowLongPtr(floating, -20) & 8) != 0;
        var percentages = Text(app.Floating.Content).Any(text => text.Contains('%') || text.Contains('％'));
        var now = DateTimeOffset.UtcNow;
        var zero = app.Monitor.Snapshots.Single(snapshot => snapshot.Provider == ProviderId.Codex).FiveHour(now)?.Used;
        var unknown = app.Monitor.Snapshots.Single(snapshot => snapshot.Provider == ProviderId.MiniMax).FiveHour(now);
        if (!Native.IsWindowVisible(main) || !Native.IsWindowVisible(floating) || !topmost || trayCount != 4 || percentages || zero != 0 || unknown is not null)
            throw new InvalidOperationException("原生窗口、置顶、托盘、无百分比或零值/未知状态验证失败");
        app.TraceSmoke("capturing-compact");
        await CaptureAsync((FrameworkElement)app.Floating.Content, Path.Combine(output, "floating-compact.png"));
        app.Floating.ShowDetail(ProviderId.Claude, pinned: true);
        await Task.Delay(700);
        var detailPercentages = Text(app.Floating.Detail.Content).Any(text => text.Contains('%') || text.Contains('％'));
        if (!app.Floating.Detail.IsDetailVisible || detailPercentages)
            throw new InvalidOperationException("浮窗详情卡未显示或包含百分比文本");
        app.TraceSmoke("capturing-expanded");
        await CaptureAsync((FrameworkElement)app.Floating.Detail.Content, Path.Combine(output, "floating-expanded.png"));
        await CaptureAsync((FrameworkElement)app.Main.Content, Path.Combine(output, "main-window.png"));
        app.Main.PageScroll.ChangeView(null, Math.Min(100, app.Main.PageScroll.ScrollableHeight), null, true);
        await Task.Delay(250);
        var offset = app.Main.PageScroll.VerticalOffset;
        app.Main.Refresh(); await Task.Delay(250);
        if (offset <= 0 || Math.Abs(app.Main.PageScroll.VerticalOffset - offset) > 2)
            throw new InvalidOperationException("刷新后滚动位置未保留");
        app.Main.SelectPage("history"); await Task.Delay(400);
        await CaptureAsync((FrameworkElement)app.Main.Content, Path.Combine(output, "history.png"));
        app.Main.SelectPage("settings"); await Task.Delay(400);
        await CaptureAsync((FrameworkElement)app.Main.Content, Path.Combine(output, "settings.png"));
        app.Main.SelectOverview(null);
        app.Floating.Hide();
        var hidden = !Native.IsWindowVisible(floating) && !app.Floating.Detail.IsDetailVisible;
        app.Floating.Show();
        if (!hidden || !Native.IsWindowVisible(floating)) throw new InvalidOperationException("浮窗隐藏/恢复失败");
        AtomicJson.Write(Path.Combine(output, "smoke.json"), new { success = true, trayIcons = trayCount, topmost,
            noFloatingPercentages = !percentages && !detailPercentages, realZeroPreserved = zero == 0, unknownPreserved = unknown is null,
            hideRestore = true, navigationPages = true, scrollPreserved = true, isolated = true, source = "anonymous-fixture", windowsVersion = Environment.OSVersion.VersionString });
    }
    private static IEnumerable<string> Text(DependencyObject element)
    {
        if (element is TextBlock block) yield return block.Text;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(element); index++)
            foreach (var text in Text(VisualTreeHelper.GetChild(element, index))) yield return text;
    }
    private static async Task CaptureAsync(FrameworkElement element, string path)
    {
        var bitmap = new RenderTargetBitmap(); await bitmap.RenderAsync(element);
        if (bitmap.PixelWidth == 0 || bitmap.PixelHeight == 0) throw new InvalidOperationException("原生 XAML 渲染未生成图像");
        var buffer = await bitmap.GetPixelsAsync(); var bytes = new byte[checked((int)buffer.Length)];
        using (var reader = DataReader.FromBuffer(buffer)) reader.ReadBytes(bytes);
        var folder = await StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(path)!);
        var file = await folder.CreateFileAsync(Path.GetFileName(path), CreationCollisionOption.ReplaceExisting);
        using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied,
            (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, 96, 96, bytes);
        await encoder.FlushAsync();
    }
}
