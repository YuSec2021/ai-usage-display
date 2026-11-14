using System.Text.Json;
using System.Text.Json.Nodes;

namespace AIUsage.Core;

public sealed record CollectorConfiguration(string Snapshot, string Settings, string InstalledCommand, JsonNode? OriginalStatusLine);

public sealed class ClaudeIntegration(string settingsPath, string collectorPath, string executablePath, string snapshotPath)
{
    public static string QuoteBash(string value) => "'" + value.Replace("\\", "/").Replace("'", "'\"'\"'") + "'";
    public string Command => $"{QuoteBash(executablePath)} --claude-statusline {QuoteBash(collectorPath)}";
    private JsonObject ReadSettings()
    {
        if (!File.Exists(settingsPath)) return new();
        using var json = AtomicJson.Read(settingsPath);
        return JsonNode.Parse(json.RootElement.GetRawText()) as JsonObject ?? throw new JsonException("Claude 设置必须为对象");
    }
    public bool IsInstalled()
    {
        try { return ReadSettings()["statusLine"]?["command"]?.GetValue<string>() == Command; }
        catch (Exception error) when (error is IOException or JsonException or InvalidOperationException) { return false; }
    }
    public void Install()
    {
        var settings = ReadSettings();
        if (IsInstalled()) return;
        var original = settings["statusLine"]?.DeepClone();
        // Write the restorable backup before changing the user's CLI settings.
        AtomicJson.Write(collectorPath, new CollectorConfiguration(snapshotPath, settingsPath, Command, original));
        settings["statusLine"] = new JsonObject { ["type"] = "command", ["command"] = Command };
        AtomicJson.Write(settingsPath, settings);
    }
    public bool Uninstall()
    {
        var settings = ReadSettings();
        if (settings["statusLine"]?["command"]?.GetValue<string>() != Command) return false;
        using var json = AtomicJson.Read(collectorPath);
        var configuration = json.Deserialize<CollectorConfiguration>() ?? throw new JsonException("集成备份无效");
        if (configuration.InstalledCommand != Command || configuration.Settings != settingsPath) return false;
        if (configuration.OriginalStatusLine is null) settings.Remove("statusLine");
        else settings["statusLine"] = configuration.OriginalStatusLine.DeepClone();
        AtomicJson.Write(settingsPath, settings);
        return true;
    }

    public static void Collect(ReadOnlyMemory<byte> input, CollectorConfiguration configuration, DateTimeOffset now)
    {
        if (input.Length > 1_048_576) throw new InvalidDataException("status line 输入超出上限");
        using var json = JsonDocument.Parse(input, new JsonDocumentOptions { MaxDepth = 64 });
        var windows = QuotaParsers.Claude(json.RootElement.Field("rate_limits"));
        var limits = new Dictionary<string, object>();
        foreach (var window in windows)
            limits[window.Minutes == 300 ? "five_hour" : "seven_day"] = new
                { used_percentage = window.Used, resets_at = window.ResetsAt?.ToUnixTimeSeconds() };
        AtomicJson.Write(configuration.Snapshot, new { collected_at = now.ToUnixTimeSeconds(), rate_limits = limits });
    }
}
