import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("appearance.theme") private var themeRawValue = AppTheme.system.rawValue
    @AppStorage(ProviderID.selectionStorageKey) private var selectedProvidersRaw = ProviderID.defaultSelectionRawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    private var selectedProviders: Set<ProviderID> {
        ProviderID.selectedProviders(from: selectedProvidersRaw)
    }

    private var filteredHistory: [DailyUsage] {
        store.history.filter { selectedProviders.contains($0.provider) }
    }

    private var displayedProviders: [ProviderID] {
        ProviderID.allCases.filter { selectedProviders.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("最近 7 天", "Last 7 days"))
                        .font(.title2.weight(.semibold))
                    Text(L10n.text("本机日志中的 token 使用量", "Token usage from local logs"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(L10n.text("刷新", "Refresh"), systemImage: "arrow.clockwise")
                }
            }

            if filteredHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 30))
                    Text(L10n.text("暂无历史数据", "No usage history"))
                        .font(.headline)
                    Text(selectedProviders.isEmpty
                         ? L10n.text("请先在设置中勾选需要收集和显示的模型。", "Select models to collect and display in Settings.")
                         : L10n.text("使用所选模型后，这里会显示最近 7 天的本地统计。", "Use a selected model to see local statistics for the last 7 days."))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    ForEach(displayedProviders) { provider in
                        HistoryProviderChart(
                            provider: provider,
                            entries: filteredHistory.filter { $0.provider == provider }
                        )
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 560)
        .appTheme(selectedTheme, systemColorScheme: systemColorScheme)
        .appLanguage(selectedLanguage)
    }
}

private struct HistoryProviderChart: View {
    let provider: ProviderID
    let entries: [DailyUsage]

    private var totalTokens: Int {
        entries.reduce(0) { $0 + $1.tokens.total }
    }

    private var chartEntries: [DailyUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let usageByDay = Dictionary(
            entries.map { (calendar.startOfDay(for: $0.date), $0.tokens) },
            uniquingKeysWith: { $0 + $1 }
        )

        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }
            return DailyUsage(
                date: date,
                provider: provider,
                tokens: usageByDay[date] ?? .zero
            )
        }
    }

    private var chartUpperBound: Int {
        let maximum = chartEntries.map(\.tokens.total).max() ?? 0
        return max(Int((Double(maximum) * 1.18).rounded(.up)), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderLogo(provider: provider, size: 16)
                Text(provider.displayName)
                    .font(.headline)
                Spacer()
                Text(L10n.text(
                    "7 天合计 \(UsageFormatting.compactNumber(totalTokens)) tokens",
                    "7-day total \(UsageFormatting.compactNumber(totalTokens)) tokens"
                ))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                    Text(L10n.text(
                        "最近 7 天暂无本地 token 记录",
                        "No local token records in the last 7 days"
                    ))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(chartEntries) { entry in
                    BarMark(
                        x: .value(L10n.text("日期", "Date"), entry.date, unit: .day),
                        y: .value("Token", entry.tokens.total),
                        width: .ratio(0.52)
                    )
                    .foregroundStyle(provider.accent)
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center) {
                        if entry.tokens.total > 0 {
                            Text(UsageFormatting.compactNumber(entry.tokens.total))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYScale(domain: 0...chartUpperBound)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) {
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Int.self) {
                                Text(UsageFormatting.compactNumber(amount))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 130)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}
