using System.Text.Json;

namespace AIUsage.Core;

public sealed class Preferences
{
    public ProviderId[] Order { get; set; } = Providers.All.ToArray();
    public ProviderId[] Selected { get; set; } = Providers.All.ToArray();
    public bool FloatingVisible { get; set; } = true;
    public bool AlwaysOnTop { get; set; } = true;
    public bool Expanded { get; set; }
    public string Theme { get; set; } = "system";
    public int RefreshSeconds { get; set; } = 30;
    public int? FloatingX { get; set; }
    public int? FloatingY { get; set; }
    public string? FloatingDisplay { get; set; }
    public IReadOnlyList<ProviderId> VisibleProviders() => Order.Concat(Providers.All).Distinct()
        .Where(id => Enum.IsDefined(id) && Selected.Contains(id)).ToArray();
    public void Normalize()
    {
        Order = (Order ?? []).Where(Enum.IsDefined).Concat(Providers.All).Distinct().ToArray();
        Selected = (Selected ?? []).Where(Enum.IsDefined).Distinct().ToArray();
        RefreshSeconds = Math.Clamp(RefreshSeconds, 15, 300);
        if (Theme is not ("light" or "dark" or "system")) Theme = "system";
    }
}

public static class AtomicJson
{
    public static void Write<T>(string path, T value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    public static JsonDocument Read(string path, int maximumBytes = 1_048_576)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (stream.Length > maximumBytes) throw new InvalidDataException("数据文件超出读取上限");
        var bytes = new byte[checked((int)stream.Length)];
        stream.ReadExactly(bytes);
        return JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 64 });
    }
    public static Preferences ReadPreferences(string path)
    {
        if (!File.Exists(path)) return new();
        try
        {
            using var json = Read(path);
            var value = json.Deserialize<Preferences>() ?? new();
            value.Normalize();
            return value;
        }
        catch (JsonException)
        {
            File.Copy(path, path + ".corrupt-" + Guid.NewGuid().ToString("N"), false);
            return new();
        }
    }
}

public sealed record ProviderPaths(string Home, string Data)
{
    public string Codex => Environment.GetEnvironmentVariable("CODEX_HOME") ?? Path.Combine(Home, ".codex");
    public string Claude => Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR") ?? Path.Combine(Home, ".claude");
    public string Kimi => Environment.GetEnvironmentVariable("KIMI_CODE_HOME") ??
        (Directory.Exists(Path.Combine(Home, ".kimi-code")) ? Path.Combine(Home, ".kimi-code") : Path.Combine(Home, ".kimi"));
    public string ClaudeSnapshot => Path.Combine(Data, "claude-snapshot.json");
}
