using System.Diagnostics;
using System.Text.Json;

namespace AIUsage.Core;

public sealed class CodexClient(Func<ProcessStartInfo?> command, TimeSpan? timeout = null)
{
    public async Task<IReadOnlyList<QuotaWindow>?> ReadAsync(CancellationToken cancellationToken)
    {
        var start = command();
        if (start is null) return null;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(timeout ?? TimeSpan.FromSeconds(8));
        using var process = new Process { StartInfo = start };
        var started = false;
        try
        {
            start.UseShellExecute = false; start.CreateNoWindow = true;
            start.RedirectStandardInput = true; start.RedirectStandardOutput = true; start.RedirectStandardError = true;
            started = process.Start();
            if (!started) return null;
            // Drain without retaining stderr, which may contain account or session information.
            var discard = DiscardAsync(process.StandardError.BaseStream, deadline.Token);
            try { return await ReadProtocolAsync(process.StandardOutput.BaseStream, process.StandardInput.BaseStream, deadline.Token); }
            finally
            {
                deadline.Cancel();
                try { await discard.WaitAsync(TimeSpan.FromMilliseconds(200)); }
                catch (Exception error) when (error is OperationCanceledException or TimeoutException or IOException) { }
            }
        }
        catch (Exception error) when (error is IOException or InvalidOperationException or System.ComponentModel.Win32Exception or OperationCanceledException)
        { cancellationToken.ThrowIfCancellationRequested(); return null; }
        finally
        {
            if (started)
            {
                try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
                catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception) { }
            }
        }
    }

    private static async Task DiscardAsync(Stream stream, CancellationToken token)
    {
        var bytes = new byte[4096];
        while (await stream.ReadAsync(bytes, token) != 0) { }
    }

    public static async Task<IReadOnlyList<QuotaWindow>?> ReadProtocolAsync(Stream output, Stream input, CancellationToken token)
    {
        async Task Send(object value)
        {
            await JsonSerializer.SerializeAsync(input, value, cancellationToken: token);
            await input.WriteAsync(new byte[] { (byte)'\n' }, token);
            await input.FlushAsync(token);
        }
        await Send(new { id = 0, method = "initialize", @params = new { clientInfo = new { name = "ai_usage_windows", version = "1" } } });
        var initialized = false;
        var buffer = new List<byte>();
        var bytes = new byte[4096];
        var total = 0;
        while (true)
        {
            var read = await output.ReadAsync(bytes, token).AsTask().WaitAsync(token);
            if (read == 0) return null;
            total += read;
            if (total > 1_048_576) return null;
            for (var index = 0; index < read; index++)
            {
                if (bytes[index] != '\n') { buffer.Add(bytes[index]); continue; }
                try
                {
                    using var json = JsonDocument.Parse(buffer.ToArray());
                    var value = json.RootElement;
                    var id = value.Field("id").Number();
                    if (id == 0 && !initialized)
                    {
                        if (value.Field("error").ValueKind != JsonValueKind.Undefined || value.Field("result").ValueKind == JsonValueKind.Undefined) return null;
                        await Send(new { method = "initialized", @params = new { } });
                        await Send(new { id = 1, method = "account/rateLimits/read" });
                        initialized = true;
                    }
                    else if (id == 1 && initialized)
                        return value.Field("error").ValueKind == JsonValueKind.Undefined
                            ? QuotaParsers.Codex(value.Field("result"), true) : null;
                }
                catch (JsonException) { }
                finally { buffer.Clear(); }
            }
        }
    }
}

public static class KimiClient
{
    public static async Task<IReadOnlyList<QuotaWindow>?> ReadAsync(HttpClient client, string? key, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(key) || key.Any(char.IsControl)) return null;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(15));
        using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.kimi.com/coding/v1/usages");
        request.Headers.Authorization = new("Bearer", key);
        request.Headers.Accept.ParseAdd("application/json");
        try
        {
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (!response.IsSuccessStatusCode) return null;
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var bytes = new MemoryStream();
            var buffer = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(buffer, deadline.Token)) > 0)
            {
                if (bytes.Length + count > 1_048_576) return null;
                bytes.Write(buffer, 0, count);
            }
            using var json = JsonDocument.Parse(bytes.ToArray());
            return QuotaParsers.Kimi(json.RootElement);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or OperationCanceledException)
        { token.ThrowIfCancellationRequested(); return null; }
    }
}
