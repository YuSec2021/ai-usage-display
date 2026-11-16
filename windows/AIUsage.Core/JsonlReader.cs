using System.Text.Json;

namespace AIUsage.Core;

public sealed record JsonlBatch(IReadOnlyList<byte[]> Lines, bool Reset, bool Limited, int BytesRead = 0);

public sealed class JsonlReader
{
    private sealed record Cursor(long Offset, long Length, long Written, long Created, byte[] Pending, bool Limited, bool Discard);
    private readonly Dictionary<string, Cursor> cursors = new(StringComparer.OrdinalIgnoreCase);
    private readonly int initialBytes;
    private readonly int maximumLine;
    public JsonlReader(int initialBytes = 16 * 1024 * 1024, int maximumLine = 1024 * 1024)
    { this.initialBytes = initialBytes; this.maximumLine = maximumLine; }

    public JsonlBatch Read(string path)
    {
        var metadata = new FileInfo(path);
        cursors.TryGetValue(path, out var previous);
        var reset = previous is null || metadata.Length < previous.Offset || metadata.CreationTimeUtc.Ticks != previous.Created ||
            (metadata.Length == previous.Length && metadata.LastWriteTimeUtc.Ticks != previous.Written);
        if (!reset && previous!.Offset == metadata.Length && previous.Length == metadata.Length && previous.Written == metadata.LastWriteTimeUtc.Ticks)
            return new([], false, previous.Limited);
        var start = reset ? Math.Max(0, metadata.Length - initialBytes) : previous!.Offset;
        var pending = reset ? [] : previous!.Pending;
        var limited = reset ? start > 0 : previous!.Limited;
        var end = Math.Min(metadata.Length, start + initialBytes);
        var data = new byte[checked((int)(end - start) + pending.Length)];
        pending.CopyTo(data, 0);
        using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        {
            stream.Seek(start, SeekOrigin.Begin);
            stream.ReadExactly(data.AsSpan(pending.Length));
        }
        var lines = new List<byte[]>();
        var begin = 0;
        var discardFirst = reset ? start > 0 : previous!.Discard;
        for (var i = 0; i < data.Length; i++)
        {
            if (data[i] != (byte)'\n') continue;
            var length = i - begin;
            if (!discardFirst && length > 0 && length <= maximumLine)
                lines.Add(data.AsSpan(begin, length).ToArray());
            if (length > maximumLine) limited = true;
            discardFirst = false;
            begin = i + 1;
        }
        var remainder = data.AsSpan(begin).ToArray();
        if (discardFirst || remainder.Length > maximumLine) { remainder = []; limited = true; discardFirst = true; }
        else if (end == metadata.Length && remainder.Length > 0)
        {
            try
            {
                using var complete = JsonDocument.Parse(remainder);
                lines.Add(remainder);
                remainder = [];
            }
            catch (JsonException) { /* Retain an incomplete trailing JSON record for the next read. */ }
        }
        // A failed read never advances the cursor or mutates provider aggregates.
        cursors[path] = new(end, metadata.Length, metadata.LastWriteTimeUtc.Ticks, metadata.CreationTimeUtc.Ticks, remainder, limited, discardFirst);
        return new(lines, reset, limited || end < metadata.Length, checked((int)(end - start)));
    }
    public void Retain(IReadOnlySet<string> paths)
    {
        foreach (var path in cursors.Keys.Where(path => !paths.Contains(path)).ToArray()) cursors.Remove(path);
    }
}
