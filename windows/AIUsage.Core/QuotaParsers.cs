using System.Globalization;
using System.Text.Json;

namespace AIUsage.Core;

public static class JsonFields
{
    public static JsonElement Field(this JsonElement value, string name) =>
        value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var field) ? field : default;
    public static string? Text(this JsonElement value) => value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    public static double? Number(this JsonElement value)
    {
        double number;
        if ((value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out number)) ||
            (value.ValueKind == JsonValueKind.String && double.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out number)))
            return double.IsFinite(number) ? number : null;
        return null;
    }
    public static long? Integer(this JsonElement value)
    {
        long count;
        if ((value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out count)) ||
            (value.ValueKind == JsonValueKind.String && long.TryParse(value.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out count)))
            return Math.Max(count, 0);
        return null;
    }
    public static long Count(this JsonElement value) => value.Integer() ?? 0;
    public static DateTimeOffset? Timestamp(this JsonElement value)
    {
        if (value.Number() is { } number && number >= -62135596800 && number <= 253402300799)
            return DateTimeOffset.FromUnixTimeSeconds((long)number);
        return DateTimeOffset.TryParse(value.Text(), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date) ? date : null;
    }
}

public static class QuotaParsers
{
    public static IReadOnlyList<QuotaWindow> Codex(JsonElement value, bool camelCase)
    {
        if (camelCase)
        {
            var buckets = value.Field("rateLimitsByLimitId");
            if (buckets.ValueKind == JsonValueKind.Object && buckets.EnumerateObject().Any()) value = buckets.Field("codex");
            else value = value.Field("rateLimits");
            var limitId = value.Field("limitId").Text();
            if (limitId is not null && limitId != "codex") return [];
        }
        var result = new List<QuotaWindow>();
        foreach (var name in new[] { "primary", "secondary" })
        {
            var window = value.Field(name);
            var used = window.Field(camelCase ? "usedPercent" : "used_percent").Number();
            var minutes = window.Field(camelCase ? "windowDurationMins" : "window_minutes").Number();
            if (used is null) continue;
            result.Add(new QuotaWindow(minutes is > 0 and <= 525600 ? (int)minutes : 0,
                Math.Clamp(used.Value, 0, 100), window.Field(camelCase ? "resetsAt" : "resets_at").Timestamp()));
        }
        return result;
    }

    public static IReadOnlyList<QuotaWindow> Claude(JsonElement limits)
    {
        var result = new List<QuotaWindow>();
        foreach (var (name, minutes) in new[] { ("five_hour", 300), ("seven_day", 10080) })
        {
            var window = limits.Field(name);
            if (window.Field("used_percentage").Number() is { } used)
                result.Add(new(minutes, Math.Clamp(used, 0, 100), window.Field("resets_at").Timestamp()));
        }
        return result;
    }

    public static IReadOnlyList<QuotaWindow> Kimi(JsonElement value)
    {
        var result = new List<QuotaWindow>();
        Add(value.Field("usage"), 10080);
        var limits = value.Field("limits");
        if (limits.ValueKind == JsonValueKind.Array)
            foreach (var limit in limits.EnumerateArray())
            {
                var window = limit.Field("window");
                if (window.Field("duration").Number() == 300 &&
                    window.Field("timeUnit").Text()?.Contains("MINUTE", StringComparison.OrdinalIgnoreCase) == true)
                    Add(limit.Field("detail"), 300);
            }
        return result;
        void Add(JsonElement detail, int minutes)
        {
            var limit = detail.Field("limit").Number();
            var used = detail.Field("used").Number();
            if (used is null && limit is { } total && detail.Field("remaining").Number() is { } remaining)
                used = total - remaining;
            if (limit is > 0 && used is not null)
            {
                var percentage = used.Value / limit.Value * 100;
                if (double.IsFinite(percentage))
                    result.Add(new(minutes, Math.Clamp(percentage, 0, 100), detail.Field("resetTime").Timestamp()));
            }
        }
    }

    public static TokenUsage Tokens(JsonElement usage, bool claude = false) => new(
        claude ? TokenUsage.Add(usage.Field("input_tokens").Count(), TokenUsage.Add(
            usage.Field("cache_read_input_tokens").Count(), usage.Field("cache_creation_input_tokens").Count())) : usage.Field("input_tokens").Count(),
        usage.Field(claude ? "cache_read_input_tokens" : "cached_input_tokens").Count(), usage.Field("output_tokens").Count());
}
