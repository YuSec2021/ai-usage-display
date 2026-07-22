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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                Chart(filteredHistory) { entry in
                    BarMark(
                        x: .value(L10n.text("日期", "Date"), entry.date, unit: .day),
                        y: .value("Token", entry.tokens.total)
                    )
                    .foregroundStyle(by: .value(L10n.text("提供商", "Provider"), entry.provider.displayName))
                    .position(by: .value(L10n.text("提供商", "Provider"), entry.provider.displayName))
                }
                .chartForegroundStyleScale(
                    domain: ProviderID.allCases.map(\.displayName),
                    range: ProviderID.allCases.map(\.accent)
                )
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
                .frame(minHeight: 300)
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 440)
        .appTheme(selectedTheme, systemColorScheme: systemColorScheme)
        .appLanguage(selectedLanguage)
    }
}
