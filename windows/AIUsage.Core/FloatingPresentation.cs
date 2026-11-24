namespace AIUsage.Core;

public readonly record struct PopoverPlacement(WindowPlacement Bounds, bool PlacedAbove, double ArrowOffsetPx);

public static class FloatingPresentation
{
    public static string RingColor(UsageSnapshot snapshot, DateTimeOffset now)
    {
        var quota = snapshot.FiveHour(now);
        if (quota is null || snapshot.IsStale(now)) return "#8B99AF";
        if (quota.Used >= 90) return "#E84141";
        return snapshot.Provider.Color();
    }

    public static string FormatResetCountdown(UsageSnapshot snapshot, DateTimeOffset now)
    {
        if (snapshot.State == SourceState.Unsupported) return "Windows 端暂不支持";
        var quota = snapshot.FiveHour(now);
        if (quota is null) return snapshot.Status(now);
        if (quota.ResetsAt is not { } reset) return "重置时间未知";
        var remaining = reset - now;
        if (remaining <= TimeSpan.Zero || remaining.TotalMinutes < 1) return "即将重置";
        var totalMinutes = (int)Math.Ceiling(remaining.TotalMinutes);
        var hours = totalMinutes / 60;
        var minutes = totalMinutes % 60;
        if (hours > 0 && minutes > 0) return $"{hours} 小时 {minutes} 分钟后重置";
        if (hours > 0) return $"{hours} 小时后重置";
        return $"{minutes} 分钟后重置";
    }

    public static string FormatUpdatedAge(UsageSnapshot snapshot, DateTimeOffset now)
    {
        if (snapshot.State == SourceState.Unsupported || snapshot.ObservedAt == DateTimeOffset.MinValue)
            return "暂无数据";
        var age = now - snapshot.ObservedAt;
        if (age < TimeSpan.FromMinutes(1)) return "刚刚更新";
        if (age < TimeSpan.FromHours(1)) return $"{(int)age.TotalMinutes} 分钟前更新";
        if (age < TimeSpan.FromDays(1)) return $"{(int)age.TotalHours} 小时前更新";
        return snapshot.ObservedAt.ToLocalTime().ToString("MM-dd HH:mm") + " 更新";
    }
}

public static class FloatingLayout
{
    public const int DockPaddingX = 19;
    public const int DockPaddingY = 9;
    public const int RingSize = 44;
    public const int RingGap = 14;
    public const int DockHeight = 64;
    public const int PopoverWidth = 240;
    public const int PopoverCardHeight = 106;
    public const int CaretHeight = 9;
    public const int PopoverHeight = PopoverCardHeight + CaretHeight;
    public const int PopoverGap = 4;
    public const int DragThresholdDip = 4;

    public static int DragThresholdPx(double scale) => Math.Max(DragThresholdDip, (int)Math.Round(DragThresholdDip * Math.Max(scale, 0.5)));

    public static bool ShouldStartDrag(int deltaX, int deltaY, double scale)
    {
        var threshold = DragThresholdPx(scale);
        return Math.Abs(deltaX) >= threshold || Math.Abs(deltaY) >= threshold;
    }

    public static (int Width, int Height) ComputeDockSize(int providerCount)
    {
        var count = Math.Max(providerCount, 1);
        var width = DockPaddingX * 2 + count * RingSize + (count - 1) * RingGap;
        return (width, DockHeight);
    }

    public static double RingCenterX(int dockWidth, int providerCount, int index)
    {
        if (providerCount <= 1) return dockWidth / 2d;
        var clamped = Math.Clamp(index, 0, providerCount - 1);
        var firstCenter = DockPaddingX + RingSize / 2d;
        var lastCenter = dockWidth - DockPaddingX - RingSize / 2d;
        if (lastCenter <= firstCenter) return dockWidth / 2d;
        return firstCenter + (lastCenter - firstCenter) * clamped / (providerCount - 1);
    }

    public static PopoverPlacement PlacePopover(WindowPlacement dock, WindowPlacement workArea,
        int popoverWidth, int popoverHeight, int gap, double ringCenterXInPixels, double arrowMarginPx = 22)
    {
        var width = Math.Min(Math.Max(popoverWidth, 1), workArea.Width);
        var height = Math.Min(Math.Max(popoverHeight, 1), workArea.Height);
        var desiredX = dock.X + (dock.Width - width) / 2;
        var x = Math.Clamp(desiredX, workArea.X, workArea.X + workArea.Width - width);

        var aboveY = dock.Y - gap - height;
        var belowY = dock.Y + dock.Height + gap;
        bool placedAbove;
        int y;
        if (aboveY >= workArea.Y)
        {
            placedAbove = true;
            y = aboveY;
        }
        else if (belowY + height <= workArea.Y + workArea.Height)
        {
            placedAbove = false;
            y = belowY;
        }
        else
        {
            placedAbove = true;
            y = Math.Clamp(aboveY, workArea.Y, workArea.Y + workArea.Height - height);
        }

        var margin = Math.Min(arrowMarginPx, width / 2d);
        var arrowOffset = Math.Clamp(dock.X + ringCenterXInPixels - x, margin, width - margin);
        return new(new(x, y, width, height), placedAbove, arrowOffset);
    }
}
