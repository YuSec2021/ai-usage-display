import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("appearance.theme") private var theme = AppTheme.system.rawValue
    @AppStorage(GlassAppearance.transparencyKey) private var glassTransparency = GlassAppearance.defaultTransparency
    @AppStorage("menubar.display") private var menuBarDisplay = MenuBarDisplayMode.bothProviders.rawValue
    @AppStorage("refresh.interval") private var refreshInterval = 30
    @AppStorage(ProviderID.selectionStorageKey) private var selectedProvidersRaw = ProviderID.defaultSelectionRawValue
    @AppStorage(ProviderID.orderStorageKey) private var providerOrderRaw = ProviderID.defaultOrderRawValue
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var integrationInstalled = ClaudeIntegrationManager.isInstalled
    @State private var operationMessage: String?
    @State private var kimiAPIKeyDraft = ""
    @StateObject private var kimiConnection = KimiConnectionModel()


    private var selectedTheme: AppTheme {
        AppTheme(rawValue: theme) ?? .system
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    private var orderedProviders: [ProviderID] {
        ProviderID.orderedProviders(from: providerOrderRaw)
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let value = build.map { "\(version) (\($0))" } ?? version
        return L10n.text("版本 \(value)", "Version \(value)")
    }

    var body: some View {
        TabView {
            generalPane
            .tabItem { Label(L10n.text("通用", "General"), systemImage: "gearshape") }

            integrationPane
            .tabItem { Label(L10n.text("集成", "Integration"), systemImage: "puzzlepiece.extension") }

            VStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 42))
                Text("AI Usage")
                    .font(.title2.weight(.semibold))
                Text(L10n.text(
                    "Codex、Claude Code、Kimi Code 与 MiniMax 本地用量监控",
                    "Local usage monitor for Codex, Claude Code, Kimi Code, and MiniMax"
                ))
                    .foregroundStyle(.secondary)
                Text(L10n.text("作者：YuSec", "Author: YuSec"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link(destination: URL(string: "https://github.com/YuSec2021/ai-usage-display")!) {
                    HStack(spacing: 6) {
                        Image("GitHubLogo")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 20, height: 20)
                        Text("ai-usage-display")
                            .font(.callout)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .help(L10n.text("在 GitHub 查看项目", "View project on GitHub"))
                .accessibilityLabel(L10n.text("在 GitHub 查看项目", "View project on GitHub"))
                GroupBox(L10n.text("版本说明", "Version notes")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(
                            "已发布：应用移动后自动更新登录启动项，避免启动旧副本。",
                            "Released: updates the login item when the app moves, preventing an older copy from launching."
                        ))
                        Text(L10n.text(
                            "本次构建：复用 Claude 短周期与周额度的重置推断遍历，保留原有零值、负值和过期规则。",
                            "This build: Share Claude quota reset inference while preserving each window’s zero and negative-boundary policy and expiry protection."
                        ))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(maxWidth: 560)
                HStack(spacing: 16) {
                    Link(
                        L10n.text("查看完整更新记录", "View full changelog"),
                        destination: URL(string: "https://github.com/YuSec2021/ai-usage-display/blob/main/docs/changelog/README.md")!
                    )
                    Link(
                        L10n.text("下载最新安装包", "Download latest installer"),
                        destination: URL(string: "https://github.com/YuSec2021/ai-usage-display/releases/latest")!
                    )
                }
                .font(.caption)
                Text(versionDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem { Label(L10n.text("关于", "About"), systemImage: "info.circle") }
        }
        .frame(width: 760, height: 680)
        .appTheme(selectedTheme, systemColorScheme: systemColorScheme)
        .appLanguage(selectedLanguage)
        .onAppear {
            kimiConnection.synchronize()
            if kimiConnection.isConfigured {
                Task { await kimiConnection.verify() }
            }

        }
    }

    private var generalPane: some View {
        ScrollView {
            VStack(spacing: 12) {
                GroupBox(L10n.text("外观", "Appearance")) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text(L10n.text("主题", "Theme"))
                            Picker(L10n.text("主题", "Theme"), selection: $theme) {
                                ForEach(AppTheme.allCases) { item in
                                    Label(item.title, systemImage: item.icon).tag(item.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        GridRow {
                            Text(L10n.text("玻璃透明度", "Glass transparency"))
                            HStack(spacing: 12) {
                                Slider(value: $glassTransparency, in: 0...1, step: 0.05) {
                                    Text(L10n.text("玻璃透明度", "Glass transparency"))
                                }
                                .accessibilityIdentifier("glassTransparencySlider")
                                Text("\(Int((glassTransparency * 100).rounded()))%")
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            Text(L10n.text(
                                "实时调整背景透明度，文字保持清晰。系统启用“减少透明度”时使用实色背景。",
                                "Adjust the background live while keeping text clear. Reduce Transparency uses a solid background."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        GridRow {
                            Text(L10n.text("语言", "Language"))
                            Picker(L10n.text("语言", "Language"), selection: $languageRawValue) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.title).tag(language.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .onChange(of: languageRawValue) { _ in
                                Task { await store.refresh() }
                            }
                        }

                        GridRow {
                            Text(L10n.text("菜单栏显示", "Menu bar"))
                            Picker(L10n.text("菜单栏显示", "Menu bar"), selection: $menuBarDisplay) {
                                ForEach(MenuBarDisplayMode.allCases) { item in
                                    Text(item.title).tag(item.rawValue)
                                }
                            }
                            .labelsHidden()
                        }

                        GridRow {
                            Text(L10n.text("显示用量", "Usage models"))
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(orderedProviders) { provider in
                                    Toggle(isOn: providerSelectionBinding(provider)) {
                                        HStack(spacing: 5) {
                                            Text(provider.displayName)
                                            ProviderLogo(provider: provider, size: 15)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }

                                Button(L10n.text("全不选", "Select none")) { updateProviderSelection([]) }
                                    .controlSize(.small)
                                    .disabled(selectedProviders.isEmpty)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            Text(L10n.text(
                                "菜单栏按详情页优先级最多显示前三个模型，其余模型仅在详情页显示。",
                                "The menu bar shows up to the first three models in detail-view priority; remaining models stay in the detail view."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox(L10n.text("行为", "Behavior")) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text(L10n.text("登录时启动", "Launch at login"))
                            Toggle(L10n.text("登录时启动", "Launch at login"), isOn: $launchAtLogin)
                                .labelsHidden()
                                .onChange(of: launchAtLogin) { newValue in
                                    updateLaunchAtLogin(newValue)
                                }
                        }

                        GridRow {
                            Text(L10n.text("刷新间隔", "Refresh interval"))
                            Picker(L10n.text("刷新间隔", "Refresh interval"), selection: $refreshInterval) {
                                Text(L10n.text("15 秒", "15 seconds")).tag(15)
                                Text(L10n.text("30 秒", "30 seconds")).tag(30)
                                Text(L10n.text("1 分钟", "1 minute")).tag(60)
                                Text(L10n.text("5 分钟", "5 minutes")).tag(300)
                            }
                            .labelsHidden()
                            .onChange(of: refreshInterval) { _ in
                                store.restart()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    private var integrationPane: some View {
        ScrollView {
            VStack(spacing: 12) {
                GroupBox("Claude Code") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.text("状态", "Status"))
                            Spacer()
                            Label(
                                integrationInstalled ? L10n.text("已安装", "Installed") : L10n.text("未安装", "Not installed"),
                                systemImage: integrationInstalled ? "checkmark.circle.fill" : "exclamationmark.circle"
                            )
                            .foregroundStyle(integrationInstalled ? Color.green : Color.orange)
                        }

                        Text(L10n.text(
                            "通过 Claude Code 官方 status line 接收额度数据，仅保存用量字段，并保留已有 status line 命令。",
                            "Receives usage limits through the official Claude Code status line, stores only usage fields, and preserves the existing status line command."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if integrationInstalled {
                            Button(L10n.text("卸载并恢复原配置", "Uninstall and restore"), role: .destructive) { uninstallIntegration() }
                        } else {
                            Button(L10n.text("安装用量集成", "Install usage integration")) { installIntegration() }
                                .buttonStyle(.borderedProminent)
                        }

                        if let operationMessage {
                            Text(operationMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("Kimi Code") {
                    VStack(alignment: .leading, spacing: 8) {
                        let kimiDetected = FileManager.default.fileExists(
                            atPath: ProviderPaths.kimiDirectory.path
                        ) || ProviderPaths.kimiDesktopLogURLs.contains {
                            FileManager.default.fileExists(atPath: $0.path)
                        }
                        HStack {
                            Text(L10n.text("本地数据", "Local data"))
                            Spacer()
                            Label(
                                kimiDetected
                                    ? L10n.text("已检测", "Detected")
                                    : L10n.text("未检测", "Not detected"),
                                systemImage: kimiDetected
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.circle"
                            )
                            .foregroundStyle(
                                kimiDetected ? Color.green : Color.orange
                            )
                        }

                        HStack(spacing: 8) {
                            SecureField(
                                kimiConnection.isConfigured
                                    ? L10n.text("API Key 已保存", "API Key saved")
                                    : "Kimi Code API Key",
                                text: $kimiAPIKeyDraft
                            )
                            .textFieldStyle(.roundedBorder)

                            Button(L10n.text("保存", "Save")) {
                                saveKimiAPIKey()
                            }
                            .disabled(
                                kimiAPIKeyDraft
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                            )

                            if kimiConnection.isConfigured {
                                Button(
                                    L10n.text("移除", "Remove"),
                                    role: .destructive
                                ) {
                                    removeKimiAPIKey()
                                }
                            }
                        }

                        HStack {
                            Label(
                                kimiConnection.statusDescription,
                                systemImage: kimiConnection.isVerified
                                    ? "checkmark.shield.fill"
                                    : (kimiConnection.isConfigured ? "clock.badge.questionmark" : "key")
                            )
                            .foregroundStyle(
                                kimiConnection.isVerified ? Color.green : Color.secondary
                            )
                            Spacer()
                            Link(
                                L10n.text("打开 Kimi Code 控制台", "Open Kimi Code Console"),
                                destination: URL(string: "https://www.kimi.com/code/console")!
                            )
                        }
                        .font(.caption)

                        Text(L10n.text(
                            "本地 Token 与订阅总额度仍从本机读取；5 小时和每周额度通过 Kimi 官方接口获取。API Key 仅保存在 macOS 钥匙串，并只发送给 api.kimi.com。",
                            "Local tokens and subscription usage remain local; 5-hour and weekly limits come from Kimi's official API. The API Key is stored only in macOS Keychain and sent only to api.kimi.com."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let message = kimiConnection.message {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("MiniMax") {
                    VStack(alignment: .leading, spacing: 8) {
                        let desktopDataDetected = FileManager.default.fileExists(
                            atPath: ProviderPaths.miniMaxDesktopCacheDirectory.path
                        )
                        HStack {
                            Text(L10n.text("Desktop 数据", "Desktop data"))
                            Spacer()
                            Label(
                                desktopDataDetected
                                    ? L10n.text("已检测", "Detected")
                                    : L10n.text("未检测", "Not detected"),
                                systemImage: desktopDataDetected
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.circle"
                            )
                            .foregroundStyle(desktopDataDetected ? Color.green : Color.orange)
                        }

                        Text(L10n.text(
                            "额度仅从 MiniMax Code 本地缓存读取。打开 MiniMax Code 的额度面板可更新缓存，无需配置 API Key。",
                            "Quotas come from the local MiniMax Code cache. Open its quota panel to update the cache; no API key is required."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox(L10n.text("隐私", "Privacy")) {
                    Text(L10n.text(
                        "Kimi API Key 仅在你主动配置后保存至 macOS 钥匙串；MiniMax 无需 API Key。不会保存提示词、回答、代码或工具参数。",
                        "The Kimi API key is saved to macOS Keychain only when explicitly configured; MiniMax needs no API key. Prompts, responses, code, and tool parameters are not saved."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func updateLaunchAtLogin(_ newValue: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(newValue)
        } catch {
            launchAtLogin = LaunchAtLoginManager.isEnabled
            operationMessage = error.localizedDescription
        }
    }

    private var selectedProviders: Set<ProviderID> {
        ProviderID.selectedProviders(from: selectedProvidersRaw)
    }

    private func providerSelectionBinding(_ provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { selectedProviders.contains(provider) },
            set: { isSelected in
                var selection = selectedProviders
                if isSelected {
                    selection.insert(provider)
                } else {
                    selection.remove(provider)
                }
                updateProviderSelection(selection)
            }
        )
    }

    private func updateProviderSelection(_ selection: Set<ProviderID>) {
        selectedProvidersRaw = ProviderID.selectionRawValue(for: selection)
        Task { await store.refresh() }
    }

    private func installIntegration() {
        do {
            try ClaudeIntegrationManager.install()
            integrationInstalled = true
            operationMessage = L10n.text("安装成功。Claude Code 下一次响应后将显示额度。", "Installed. Usage limits will appear after the next Claude Code response.")
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    private func uninstallIntegration() {
        do {
            try ClaudeIntegrationManager.uninstall()
            integrationInstalled = false
            operationMessage = L10n.text("已卸载，并恢复安装前的 status line 配置。", "Uninstalled and restored the previous status line configuration.")
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    private func saveKimiAPIKey() {
        guard kimiConnection.save(kimiAPIKeyDraft) else { return }
        kimiAPIKeyDraft = ""
        Task {
            if await kimiConnection.verify(showSuccessMessage: true) {
                await store.refresh(providers: [.kimiCode])
            }
        }
    }

    private func removeKimiAPIKey() {
        guard kimiConnection.remove() else { return }
        kimiAPIKeyDraft = ""
        Task { await store.refresh(providers: [.kimiCode]) }
    }
}
