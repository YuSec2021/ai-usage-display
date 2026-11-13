import SwiftUI
import AppKit

struct UsageRing: View {
    let provider: ProviderID
    let window: RateLimitWindow?
    var size: CGFloat = 74
    var isStale = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineWidth: CGFloat { size > 40 ? 5 : 2.5 }
    private var color: Color {
        if isStale || window == nil { return .secondary }
        if (window?.usedPercentage ?? 0) >= 90 { return .red }
        if (window?.usedPercentage ?? 0) >= 75 { return .orange }
        return provider.accent
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.09), style: StrokeStyle(
                    lineWidth: lineWidth,
                    dash: window == nil ? [3, 4] : []
                ))
            if let window, !window.isUnlimited {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: window.usedPercentage / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: isStale ? [3, 3] : []))
                    .rotationEffect(.degrees(-90))
            }
            ProviderLogo(provider: provider, size: size * 0.47)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: window?.usedPercentage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName) · \(window?.label ?? L10n.text("5 小时", "5 hours"))")
        .accessibilityValue(usageDescription)
        .help(usageDescription)
    }

    private var usageDescription: String {
        guard let window else { return L10n.text("暂无 5 小时额度数据", "5-hour quota unavailable") }
        let prefix = isStale ? L10n.text("数据可能过期。", "Data may be outdated. ") : ""
        if window.isUnlimited { return prefix + L10n.text("无限制", "Unlimited") }
        return prefix + L10n.text(
            "已使用百分之\(Int(window.usedPercentage.rounded()))，\(UsageFormatting.resetDescription(window.resetsAt, precision: window.resetTimePrecision))",
            "\(Int(window.usedPercentage.rounded())) percent used. \(UsageFormatting.resetDescription(window.resetsAt, precision: window.resetTimePrecision))"
        )
    }
}

@MainActor
enum MenuBarRingImage {
    static func make(snapshots: [UsageSnapshot], showsProgress: Bool = true) -> NSImage? {
        guard !snapshots.isEmpty else { return nil }
        let size: CGFloat = 22
        let spacing: CGFloat = 5
        let items = snapshots.map { snapshot in
            (
                logo: NSImage(named: snapshot.provider.logoAssetName),
                usage: snapshot.fiveHourWindow()?.usedPercentage,
                stale: snapshot.availability.isStale
            )
        }
        let image = NSImage(size: NSSize(width: size * CGFloat(items.count) + spacing * CGFloat(items.count - 1), height: size), flipped: false) { _ in
            for (index, item) in items.enumerated() {
                let x = CGFloat(index) * (size + spacing)
                let center = NSPoint(x: x + size / 2, y: size / 2)
                if showsProgress {
                    let track = NSBezierPath(ovalIn: NSRect(x: x + 1.5, y: 1.5, width: 19, height: 19))
                    track.lineWidth = 1.75
                    if item.usage == nil { track.setLineDash([2, 2], count: 2, phase: 0) }
                    NSColor.black.withAlphaComponent(0.22).setStroke()
                    track.stroke()
                    if let usage = item.usage, usage > 0 {
                        let progress = NSBezierPath()
                        progress.appendArc(withCenter: center, radius: 9.5, startAngle: 90, endAngle: 90 - CGFloat(usage) * 3.6, clockwise: true)
                        progress.lineWidth = 1.75
                        progress.lineCapStyle = .round
                        if item.stale { progress.setLineDash([2, 2], count: 2, phase: 0) }
                        NSColor.black.setStroke()
                        progress.stroke()
                    }
                }
                item.logo?.draw(in: NSRect(x: x + 5, y: 5, width: 12, height: 12), from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
