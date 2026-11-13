import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let storageKey = "appearance.language"
    var id: Self { self }

    var title: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    static var current: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
        return rawValue.flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
    }
}

enum L10n {
    static func text(_ simplifiedChinese: String, _ english: String) -> String {
        AppLanguage.current == .english ? english : simplifiedChinese
    }
}

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claudeCode
    case kimiCode
    case miniMax

    var id: Self { self }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .kimiCode: "Kimi Code"
        case .miniMax: "MiniMax"
        }
    }

    var accent: Color {
        switch self {
        case .codex: Color(red: 0.20, green: 0.68, blue: 0.25)
        case .claudeCode: Color(red: 0.96, green: 0.38, blue: 0.02)
        case .kimiCode: Color(red: 0.20, green: 0.45, blue: 0.96)
        case .miniMax: Color(red: 0.95, green: 0.10, blue: 0.48)
        }
    }

    /// Centralized provider metadata keeps selection and display extensible.
    var logoAssetName: String {
        switch self {
        case .codex: "ChatGPTLogo"
        case .claudeCode: "ClaudeLogo"
        case .kimiCode: "KimiLogo"
        case .miniMax: "MiniMaxLogo"
        }
    }

    var logoUsesPrimaryColor: Bool { self == .codex || self == .kimiCode }

    static let selectionStorageKey = "providers.selected"
    static let orderStorageKey = "providers.order"
    static let menuBarDisplayLimit = 3

    static var defaultSelectionRawValue: String {
        allCases.map(\.rawValue).joined(separator: ",")
    }

    static var defaultOrderRawValue: String {
        orderRawValue(for: allCases)
    }

    static func selectedProviders(from rawValue: String) -> Set<ProviderID> {
        Set(rawValue.split(separator: ",").compactMap { ProviderID(rawValue: String($0)) })
    }

    static func selectionRawValue(for providers: Set<ProviderID>) -> String {
        allCases.filter { providers.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    /// Restores the user's preferred order while appending providers introduced
    /// by a newer app version so an older preference never hides new models.
    static func orderedProviders(from rawValue: String) -> [ProviderID] {
        var seen = Set<ProviderID>()
        let stored = rawValue.split(separator: ",").compactMap { value -> ProviderID? in
            guard let provider = ProviderID(rawValue: String(value)),
                  seen.insert(provider).inserted else {
                return nil
            }
            return provider
        }
        return stored + allCases.filter { !seen.contains($0) }
    }

    static func orderRawValue(for providers: [ProviderID]) -> String {
        providers.map(\.rawValue).joined(separator: ",")
    }

    /// The detail view keeps every selected provider, while the constrained
    /// system menu bar uses only the first selected providers in user order.
    static func menuBarProviders(
        orderRawValue: String,
        selectedProviders: Set<ProviderID>
    ) -> [ProviderID] {
        Array(
            orderedProviders(from: orderRawValue)
                .filter { selectedProviders.contains($0) }
                .prefix(menuBarDisplayLimit)
        )
    }

    static func moving(
        _ provider: ProviderID,
        toPositionOf destination: ProviderID,
        in providers: [ProviderID]
    ) -> [ProviderID] {
        guard provider != destination,
              let sourceIndex = providers.firstIndex(of: provider),
              let destinationIndex = providers.firstIndex(of: destination) else {
            return providers
        }

        var reordered = providers
        reordered.remove(at: sourceIndex)
        reordered.insert(provider, at: min(destinationIndex, reordered.endIndex))
        return reordered
    }
}

enum WindowKind: String, Codable, Sendable {
    case short
    case long
}

enum ResetTimePrecision: String, Codable, Sendable {
    case exact
    case day
}

struct RateLimitWindow: Codable, Equatable, Sendable, Identifiable {
    let kind: WindowKind
    let label: String
    let usedPercentage: Double
    let resetsAt: Date?
    let durationMinutes: Int?
    let resetTimePrecision: ResetTimePrecision
    let isUnlimited: Bool

    var id: String { "\(kind.rawValue)-\(label)" }

    init(
        kind: WindowKind,
        label: String,
        usedPercentage: Double,
        resetsAt: Date?,
        durationMinutes: Int? = nil,
        resetTimePrecision: ResetTimePrecision = .exact,
        isUnlimited: Bool = false
    ) {
        self.kind = kind
        self.label = label
        self.usedPercentage = min(max(usedPercentage, 0), 100)
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
        self.resetTimePrecision = resetTimePrecision
        self.isUnlimited = isUnlimited
    }

    enum CodingKeys: String, CodingKey {
        case kind, label, usedPercentage, resetsAt, durationMinutes, resetTimePrecision, isUnlimited
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try values.decode(WindowKind.self, forKey: .kind),
            label: try values.decode(String.self, forKey: .label),
            usedPercentage: try values.decode(Double.self, forKey: .usedPercentage),
            resetsAt: try values.decodeIfPresent(Date.self, forKey: .resetsAt),
            durationMinutes: try values.decodeIfPresent(Int.self, forKey: .durationMinutes),
            resetTimePrecision: try values.decodeIfPresent(ResetTimePrecision.self, forKey: .resetTimePrecision) ?? .exact,
            isUnlimited: try values.decodeIfPresent(Bool.self, forKey: .isUnlimited) ?? false
        )
    }
}

struct TokenUsage: Codable, Equatable, Sendable {
    /// Total input tokens, including the cached-input subset.
    var input: Int
    /// Cached tokens are informational and already included in `input`.
    var cachedInput: Int
    var output: Int
    var reasoningOutput: Int

    static let zero = TokenUsage(input: 0, cachedInput: 0, output: 0, reasoningOutput: 0)

    var total: Int { input + output }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            output: lhs.output + rhs.output,
            reasoningOutput: lhs.reasoningOutput + rhs.reasoningOutput
        )
    }
}

struct DailyUsage: Codable, Equatable, Sendable, Identifiable {
    let date: Date
    let provider: ProviderID
    var tokens: TokenUsage

    var id: String { "\(provider.rawValue)-\(date.timeIntervalSince1970)" }
}

enum ProviderAvailability: Equatable, Sendable {
    case ready(lastUpdated: Date)
    case stale(lastUpdated: Date)
    case waitingForFirstSample
    case cliNotInstalled
    case integrationNotInstalled
    case permissionDenied
    case unsupportedFormat
    case failed(String)

    var message: String {
        switch self {
        case .ready: L10n.text("数据正常", "Data available")
        case .stale(let lastUpdated): L10n.text(
            "数据可能过期 · \(UsageFormatting.updatedDescription(lastUpdated))",
            "May be outdated · \(UsageFormatting.updatedDescription(lastUpdated))"
        )
        case .waitingForFirstSample: L10n.text("运行一次 CLI 后显示", "Run the CLI once to display usage")
        case .cliNotInstalled: L10n.text("未检测到 CLI", "CLI not detected")
        case .integrationNotInstalled: L10n.text("尚未安装用量集成", "Usage integration not installed")
        case .permissionDenied: L10n.text("没有目录读取权限", "Folder access denied")
        case .unsupportedFormat: L10n.text("当前数据格式暂不支持", "Unsupported data format")
        case .failed(let message): message
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    /// Stale snapshots still contain the last successfully decoded quota.
    /// Keep them eligible for aggregate menu-bar display while the UI clearly
    /// labels the provider as outdated.
    var hasUsableData: Bool {
        isReady || isStale
    }
}

struct UsageSnapshot: Equatable, Sendable, Identifiable {
    let provider: ProviderID
    var windows: [RateLimitWindow]
    var todayTokens: TokenUsage?
    var estimatedCostUSD: Decimal?
    var observedAt: Date
    var availability: ProviderAvailability

    var id: ProviderID { provider }

    func fiveHourWindow(at date: Date = Date()) -> RateLimitWindow? {
        guard availability.hasUsableData else { return nil }
        return windows.first {
            $0.kind == .short && $0.durationMinutes == 300
                && $0.usedPercentage.isFinite
                && ($0.resetsAt.map { $0 > date } ?? true)
        }
    }

    func fiveHourStatusDescription(at date: Date = Date()) -> String {
        if let window = fiveHourWindow(at: date) {
            if window.isUnlimited { return L10n.text("无限制", "Unlimited") }
            return UsageFormatting.resetDescription(window.resetsAt)
        }
        if windows.contains(where: {
            $0.kind == .short && $0.durationMinutes == 300 && ($0.resetsAt.map { $0 <= date } ?? false)
        }) {
            return provider == .codex
                ? L10n.text("上个周期已结束，等待 Codex 更新额度", "Previous window ended; waiting for Codex quota update")
                : L10n.text("上个周期已结束，等待更新额度", "Previous window ended; waiting for quota update")
        }
        return L10n.text("暂无 5 小时额度数据", "5-hour quota unavailable")
    }

    static func empty(_ provider: ProviderID, availability: ProviderAvailability) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            windows: [],
            todayTokens: nil,
            estimatedCostUSD: nil,
            observedAt: .distantPast,
            availability: availability
        )
    }
}

struct ProviderResult: Sendable {
    let snapshot: UsageSnapshot
    let dailyUsage: [DailyUsage]
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: L10n.text("跟随系统", "System")
        case .light: L10n.text("浅色", "Light")
        case .dark: L10n.text("深色", "Dark")
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        colorScheme ?? systemColorScheme
    }
}

private struct AppThemeModifier: ViewModifier {
    let theme: AppTheme
    let systemColorScheme: ColorScheme

    private var resolvedColorScheme: ColorScheme {
        theme.resolvedColorScheme(systemColorScheme: systemColorScheme)
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(resolvedColorScheme == .dark ? Color.white : Color.black)
            .background { AppGlassBackground() }
            .modifier(ClearWindowBackground())
            .environment(\.colorScheme, resolvedColorScheme)
            .preferredColorScheme(resolvedColorScheme)
    }
}

extension View {
    func appTheme(_ theme: AppTheme, systemColorScheme: ColorScheme) -> some View {
        modifier(AppThemeModifier(theme: theme, systemColorScheme: systemColorScheme))
    }
}

private struct AppLanguageModifier: ViewModifier {
    let language: AppLanguage

    func body(content: Content) -> some View {
        content.environment(\.locale, language.locale)
    }
}

extension View {
    func appLanguage(_ language: AppLanguage) -> some View {
        modifier(AppLanguageModifier(language: language))
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly
    case bothProviders
    case highestUsage

    var id: Self { self }

    func displayedSnapshots(from snapshots: [UsageSnapshot]) -> [UsageSnapshot] {
        switch self {
        case .iconOnly:
            return Array(snapshots.prefix(1))
        case .bothProviders:
            return snapshots
        case .highestUsage:
            let available = snapshots.filter { $0.fiveHourWindow() != nil }
            let highest = available.max {
                ($0.fiveHourWindow()?.usedPercentage ?? 0) < ($1.fiveHourWindow()?.usedPercentage ?? 0)
            }
            return highest.map { [$0] } ?? Array(snapshots.prefix(1))
        }
    }

    var title: String {
        switch self {
        case .iconOnly: L10n.text("仅模型图标", "Model icon only")
        case .bothProviders: L10n.text("各模型额度圆环", "Each model's quota ring")
        case .highestUsage: L10n.text("最高 5 小时额度圆环", "Highest 5-hour quota ring")
        }
    }
}
