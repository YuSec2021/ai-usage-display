import SwiftUI

struct ProviderCard: View {
    let snapshot: UsageSnapshot
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var showsDragHandle = false

    private var accent: Color { snapshot.provider.accent }

    private var fiveHourWindow: RateLimitWindow? { snapshot.fiveHourWindow() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                UsageRing(
                    provider: snapshot.provider,
                    window: fiveHourWindow,
                    isStale: snapshot.availability.isStale
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.provider.displayName)
                        .font(.title3.weight(.semibold))
                    Text(L10n.text("5 小时已用额度", "5-hour quota used"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(snapshot.fiveHourStatusDescription())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if showsDragHandle {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 32)
                        .contentShape(Rectangle())
                        .help(L10n.text("拖动以调整显示顺序", "Drag to reorder"))
                        .accessibilityLabel(L10n.text("拖动以调整显示顺序", "Drag to reorder"))
                }
            }

            if snapshot.windows.isEmpty {
                emptyState
            }
            if !snapshot.availability.isReady, !snapshot.windows.isEmpty {
                Text(snapshot.availability.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.windows.filter { $0.kind != .short || $0.durationMinutes != 300 }) { window in
                HStack(spacing: 10) {
                    UsageRing(provider: snapshot.provider, window: window, size: 30, isStale: snapshot.availability.isStale)
                    Text(window.label)
                        .font(.callout)
                    Spacer()
                    Text(UsageFormatting.resetDescription(window.resetsAt, precision: window.resetTimePrecision))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .padding(18)
        .glassCard()
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
        if snapshot.provider == .claudeCode, snapshot.availability.isStale {
            return L10n.text(
                "额度数据已过期，请在 Claude Code 中完成一次对话后刷新",
                "Quota data expired. Complete a Claude Code conversation, then refresh."
            )
        }
        if snapshot.provider != .miniMax, snapshot.availability.isReady {
            return L10n.text(
                "暂无额度数据，仅统计本地 Token",
                "Quota unavailable; local tokens only"
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
