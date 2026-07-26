import SwiftUI

struct ProviderCard: View {
    let snapshot: UsageSnapshot
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var showsDragHandle = false

    private var accent: Color { snapshot.provider.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(snapshot.availability.isReady ? accent : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(snapshot.provider.displayName)
                    .font(.headline)
                ProviderLogo(provider: snapshot.provider)
                Spacer()
                if !snapshot.availability.isReady {
                    Text(snapshot.availability.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showsDragHandle {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .help(L10n.text("拖动以调整显示顺序", "Drag to reorder"))
                        .accessibilityLabel(L10n.text("拖动以调整显示顺序", "Drag to reorder"))
                }
            }

            if snapshot.windows.isEmpty {
                emptyState
            } else {
                ForEach(snapshot.windows) { window in
                    RateWindowRow(window: window, accent: accent, isStale: snapshot.availability.isStale)
                }
            }

            if snapshot.provider != .miniMax {
                Divider()

                HStack {
                    Text(L10n.text("今日 Token", "Tokens today"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(snapshot.todayTokens.map { UsageFormatting.compactNumber($0.total) } ?? "—")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                if let tokens = snapshot.todayTokens, tokens.total > 0 {
                    HStack(spacing: 12) {
                        tokenDetail(L10n.text("输入", "Input"), tokens.input)
                        tokenDetail(L10n.text("缓存", "Cached"), tokens.cachedInput)
                        tokenDetail(L10n.text("输出", "Output"), tokens.output)
                    }
                }
            }
        }
        .padding(14)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(emptyStateMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(minHeight: 42)
    }

    private var emptyStateMessage: String {
        if snapshot.provider == .kimiCode, snapshot.availability.isReady {
            return L10n.text(
                "暂无额度百分比，仅统计本地 Token",
                "Local tokens only; quota percentage unavailable"
            )
        }
        return snapshot.availability.message
    }

    private func tokenDetail(_ title: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text(UsageFormatting.compactNumber(value))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ProviderLogo: View {
    let provider: ProviderID
    var size: CGFloat = 16
    var monochrome = false

    var body: some View {
        Image(provider.logoAssetName)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(monochrome || provider.logoUsesPrimaryColor ? Color.primary : provider.accent)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct RateWindowRow: View {
    let window: RateLimitWindow
    let accent: Color
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(window.label)
                    .font(.callout)
                Spacer()
                Text("\(isStale ? "~" : "")\(Int(window.usedPercentage.rounded()))%")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(usageColor)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                ProgressView(value: window.usedPercentage, total: 100)
                    .progressViewStyle(.linear)
                    .tint(usageColor)
                Text(resetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 104, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text(
            "\(window.label)额度已使用百分之\(Int(window.usedPercentage.rounded()))，\(resetDescription)",
            "\(window.label), \(Int(window.usedPercentage.rounded())) percent used, \(resetDescription)"
        ))
    }

    private var resetDescription: String {
        UsageFormatting.resetDescription(
            window.resetsAt,
            precision: window.resetTimePrecision
        )
    }

    private var usageColor: Color {
        if isStale { return .secondary }
        if window.usedPercentage >= 90 { return .red }
        if window.usedPercentage >= 75 { return .orange }
        return accent
    }
}
