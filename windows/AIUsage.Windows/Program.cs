using System.Diagnostics;
using System.Text.Json;
using AIUsage.Core;
using Microsoft.UI.Dispatching;

namespace AIUsage.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--claude-statusline") return CollectAsync(args[1]).GetAwaiter().GetResult();
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000)) return 1;
        using var instance = new Mutex(true, args.Contains("--smoke-test") ? "Local\\AIUsage.Smoke." + Guid.NewGuid() :
            "Local\\AIUsage.Windows." + Environment.UserName, out var created);
        if (!created)
        {
            var existing = Native.FindWindowW(null, "AI Usage");
            if (existing != 0) { Native.ShowWindow(existing, 9); Native.SetForegroundWindow(existing); }
            return 0;
        }
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Microsoft.UI.Xaml.Application.Start(parameters =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            _ = new App(args);
        });
        return 0;
    }

    private static async Task<int> CollectAsync(string path)
    {
        try
        {
            using var json = AtomicJson.Read(path);
            var configuration = json.Deserialize<CollectorConfiguration>() ?? throw new JsonException();
            using var input = Console.OpenStandardInput();
            using var bytes = new MemoryStream();
            var buffer = new byte[8192];
            int read;
            while ((read = await input.ReadAsync(buffer)) > 0)
            {
                if (bytes.Length + read > 1_048_576) return 1;
                bytes.Write(buffer, 0, read);
            }
            try { ClaudeIntegration.Collect(bytes.ToArray(), configuration, DateTimeOffset.UtcNow); }
            catch (JsonException) { /* Preserve the original status line even if this sample is invalid. */ }
            var command = configuration.OriginalStatusLine?["command"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(command)) return 0;
            var bash = WindowsPaths.FindBash();
            if (bash is null) return 1;
            using var process = new Process { StartInfo = new(bash) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true } };
            process.StartInfo.ArgumentList.Add("-lc"); process.StartInfo.ArgumentList.Add(command);
            if (!process.Start()) return 1;
            await process.StandardInput.BaseStream.WriteAsync(bytes.ToArray());
            process.StandardInput.Close();
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try { await process.WaitForExitAsync(timeout.Token); }
            catch (OperationCanceledException) { if (!process.HasExited) process.Kill(true); return 1; }
            return process.ExitCode;
        }
        catch (Exception error) when (error is IOException or JsonException or InvalidOperationException or System.ComponentModel.Win32Exception)
        { return 1; }
    }
}
