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

    var id: Self { self }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }

    var accent: Color {
        switch self {
        case .codex: Color(red: 0.20, green: 0.68, blue: 0.25)
        case .claudeCode: Color(red: 0.96, green: 0.38, blue: 0.02)
        }
    }

    /// Centralized provider metadata keeps selection and display extensible.
    var logoAssetName: String {
        switch self {
        case .codex: "ChatGPTLogo"
        case .claudeCode: "ClaudeLogo"
        }
    }

    var logoUsesPrimaryColor: Bool { self == .codex }

    static let selectionStorageKey = "providers.selected"

    static var defaultSelectionRawValue: String {
        allCases.map(\.rawValue).joined(separator: ",")
    }

    static func selectedProviders(from rawValue: String) -> Set<ProviderID> {
        Set(rawValue.split(separator: ",").compactMap { ProviderID(rawValue: String($0)) })
    }

    static func selectionRawValue(for providers: Set<ProviderID>) -> String {
        allCases.filter { providers.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}

enum WindowKind: String, Codable, Sendable {
    case short
    case long
}

struct RateLimitWindow: Codable, Equatable, Sendable, Identifiable {
    let kind: WindowKind
    let label: String
    let usedPercentage: Double
    let resetsAt: Date?
    let durationMinutes: Int?

    var id: WindowKind { kind }

    init(kind: WindowKind, label: String, usedPercentage: Double, resetsAt: Date?, durationMinutes: Int? = nil) {
        self.kind = kind
        self.label = label
        self.usedPercentage = min(max(usedPercentage, 0), 100)
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }
}

struct TokenUsage: Codable, Equatable, Sendable {
    var input: Int
    var cachedInput: Int
    var output: Int
    var reasoningOutput: Int

    static let zero = TokenUsage(input: 0, cachedInput: 0, output: 0, reasoningOutput: 0)

    var total: Int { input + cachedInput + output }

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
}

struct UsageSnapshot: Equatable, Sendable, Identifiable {
    let provider: ProviderID
    var windows: [RateLimitWindow]
    var todayTokens: TokenUsage?
    var estimatedCostUSD: Decimal?
    var observedAt: Date
    var availability: ProviderAvailability

    var id: ProviderID { provider }

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
            .environment(\.colorScheme, resolvedColorScheme)
            .preferredColorScheme(resolvedColorScheme)
            .foregroundStyle(resolvedColorScheme == .dark ? Color.white : Color.black)
            .background(resolvedColorScheme == .dark ? Color(red: 0.075, green: 0.075, blue: 0.085) : Color.white)
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

    var title: String {
        switch self {
        case .iconOnly: L10n.text("仅图标", "Icon only")
        case .bothProviders: L10n.text("显示各模型", "Each model")
        case .highestUsage: L10n.text("最高用量", "Highest usage")
        }
    }
}
