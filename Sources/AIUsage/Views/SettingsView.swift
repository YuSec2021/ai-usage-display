import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("appearance.theme") private var theme = AppTheme.system.rawValue
    @AppStorage("menubar.display") private var menuBarDisplay = MenuBarDisplayMode.highestUsage.rawValue
    @AppStorage("refresh.interval") private var refreshInterval = 30
    @AppStorage(ProviderID.selectionStorageKey) private var selectedProvidersRaw = ProviderID.defaultSelectionRawValue
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var integrationInstalled = ClaudeIntegrationManager.isInstalled
    @State private var operationMessage: String?

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: theme) ?? .system
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
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
                Text(L10n.text("Codex 与 Claude Code 本地用量监控", "Local usage monitor for Codex and Claude Code"))
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
                Text(versionDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem { Label(L10n.text("关于", "About"), systemImage: "info.circle") }
        }
        .frame(width: 560, height: 360)
        .appTheme(selectedTheme, systemColorScheme: systemColorScheme)
        .appLanguage(selectedLanguage)
    }

    private var generalPane: some View {
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
                        HStack(spacing: 14) {
                            ForEach(ProviderID.allCases) { provider in
                                Toggle(isOn: providerSelectionBinding(provider)) {
                                    HStack(spacing: 5) {
                                        Text(provider.displayName)
                                        ProviderLogo(provider: provider, size: 15)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }

                            Spacer(minLength: 0)
                            Button(L10n.text("全不选", "Select none")) { updateProviderSelection([]) }
                                .controlSize(.small)
                                .disabled(selectedProviders.isEmpty)
                        }
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

    private var integrationPane: some View {
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

            GroupBox(L10n.text("隐私", "Privacy")) {
                Text(L10n.text(
                    "不会读取登录凭证，也不会保存提示词、回答、代码或工具参数。",
                    "The app does not read login credentials or save prompts, responses, code, or tool parameters."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
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
}
