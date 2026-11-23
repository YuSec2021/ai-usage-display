using AIUsage.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.UI;

namespace AIUsage.Windows;

internal static class RingView
{
    public static SolidColorBrush Brush(string hex, byte alpha = 255)
    {
        hex = hex.TrimStart('#');
        return new(Color.FromArgb(alpha, Convert.ToByte(hex[..2], 16), Convert.ToByte(hex[2..4], 16), Convert.ToByte(hex[4..6], 16)));
    }

    public static Grid Create(UsageSnapshot snapshot, double size, Action? click = null,
        bool dockStyle = false, bool darkTheme = false)
    {
        var root = new Grid { Width = size, Height = size, Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent) };
        var now = DateTimeOffset.UtcNow;
        var quota = snapshot.FiveHour(now);
        var stale = snapshot.IsStale(now);
        var strokeWidth = dockStyle ? 2.6 : (size > 40 ? 4 : 2);
        var trackColor = dockStyle
            ? (darkTheme ? Color.FromArgb(62, 200, 216, 240) : Color.FromArgb(46, 96, 117, 152))
            : Color.FromArgb(75, 128, 128, 128);
        var inset = dockStyle ? 0.4 : 1.0;
        var track = new Ellipse
        {
            Stroke = new SolidColorBrush(trackColor),
            StrokeThickness = strokeWidth,
            Margin = new Thickness(inset)
        };
        if (quota is null)
        {
            track.StrokeDashArray = dockStyle ? new DoubleCollection { 1.15, 1.46 } : new DoubleCollection { 2, 2 };
            if (dockStyle) track.StrokeDashCap = PenLineCap.Round;
        }
        root.Children.Add(track);

        if (quota is { Fraction: > 0 })
        {
            var color = FloatingPresentation.RingColor(snapshot, now);
            Shape progress;
            if (quota.Fraction >= 1) progress = new Ellipse { Margin = new Thickness(inset) };
            else
            {
                var center = size / 2;
                var radius = center - inset - strokeWidth / 2;
                var angle = quota.Fraction * Math.PI * 2;
                var figure = new PathFigure { StartPoint = new Point(center, inset + strokeWidth / 2), IsClosed = false };
                figure.Segments.Add(new ArcSegment
                {
                    Point = new Point(center + radius * Math.Sin(angle), center - radius * Math.Cos(angle)),
                    Size = new Size(radius, radius),
                    SweepDirection = SweepDirection.Clockwise,
                    IsLargeArc = quota.Fraction > .5
                });
                var geometry = new PathGeometry();
                geometry.Figures.Add(figure);
                progress = new Microsoft.UI.Xaml.Shapes.Path { Data = geometry };
            }
            progress.Stroke = Brush(color);
            progress.StrokeThickness = strokeWidth;
            progress.StrokeStartLineCap = PenLineCap.Round;
            progress.StrokeEndLineCap = PenLineCap.Round;
            if (stale) progress.StrokeDashArray = new DoubleCollection { 2, 2 };
            root.Children.Add(progress);
        }

        if (dockStyle)
        {
            root.Children.Add(new BitmapIcon
            {
                UriSource = new Uri("ms-appx:///Assets/" + snapshot.Provider.Logo() + ".png"),
                ShowAsMonochrome = true,
                Foreground = Brush(darkTheme ? "#EEF3FA" : "#253040"),
                Width = Math.Round(size * 0.41),
                Height = Math.Round(size * 0.41),
                Opacity = quota is null ? 0.70 : 0.82,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            });
        }
        else
        {
            // A neutral logo tile keeps the original vector-derived artwork legible in both themes.
            var tile = new Border
            {
                Width = size * .51,
                Height = size * .51,
                CornerRadius = new CornerRadius(6),
                Background = new SolidColorBrush(Color.FromArgb(245, 248, 248, 248)),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            tile.Child = new Image { Source = new BitmapImage(new Uri("ms-appx:///Assets/" + snapshot.Provider.Logo() + ".png")), Margin = new Thickness(2) };
            root.Children.Add(tile);
        }

        AutomationProperties.SetName(root, snapshot.Provider.Name() + "，5 小时额度圆环，" + snapshot.Status(now));
        if (!dockStyle)
            ToolTipService.SetToolTip(root, snapshot.Provider.Name() + " · " + snapshot.Status(now));
        if (click is not null)
        {
            root.IsTabStop = true;
            root.Tapped += (_, args) => { click(); args.Handled = true; };
            root.KeyDown += (_, args) =>
            {
                if (args.Key is global::Windows.System.VirtualKey.Enter or global::Windows.System.VirtualKey.Space)
                {
                    click();
                    args.Handled = true;
                }
            };
        }
        return root;
    }
}
