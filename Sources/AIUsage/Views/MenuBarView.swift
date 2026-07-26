import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("appearance.theme") private var themeRawValue = AppTheme.system.rawValue
    @AppStorage(ProviderID.selectionStorageKey) private var selectedProvidersRaw = ProviderID.defaultSelectionRawValue
    @AppStorage(ProviderID.orderStorageKey) private var providerOrderRaw = ProviderID.defaultOrderRawValue
    @State private var integrationMessage: String?
    @State private var draggedProvider: ProviderID?
    @State private var dropTargetProvider: ProviderID?
    @State private var providerCardFrames: [ProviderID: CGRect] = [:]
    @State private var dragReferenceFrames: [ProviderID: CGRect] = [:]
    @State private var dragTranslation: CGSize = .zero

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    private var selectedProviders: Set<ProviderID> {
        ProviderID.selectedProviders(from: selectedProvidersRaw)
    }

    private var displayedProviders: [ProviderID] {
        ProviderID.orderedProviders(from: providerOrderRaw)
            .filter { selectedProviders.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 12) {
                    if selectedProviders.isEmpty {
                        noProvidersSelected
                    } else {
                        if displayedProviders.count > 1 {
                            Label(
                                L10n.text("上下拖动卡片可调整显示顺序", "Drag cards vertically to reorder"),
                                systemImage: "arrow.up.arrow.down"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(displayedProviders) { provider in
                            providerCard(for: provider)
                                .contentShape(Rectangle())
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: ProviderCardFramePreferenceKey.self,
                                            value: [provider: proxy.frame(in: .named("providerList"))]
                                        )
                                    }
                                }
                                .offset(draggedProvider == provider ? dragTranslation : .zero)
                                .opacity(draggedProvider == provider ? 0.94 : 1)
                                .scaleEffect(dropTargetProvider == provider ? 1.015 : 1)
                                .zIndex(draggedProvider == provider ? 10 : 0)
                                .shadow(
                                    color: draggedProvider == provider ? .black.opacity(0.22) : .clear,
                                    radius: 10,
                                    y: 5
                                )
                                .overlay {
                                    if dropTargetProvider == provider {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(provider.accent, lineWidth: 2)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .overlay(alignment: .top) {
                                    if dropTargetProvider == provider {
                                        Capsule()
                                            .fill(provider.accent)
                                            .frame(width: 54, height: 4)
                                            .offset(y: -7)
                                            .shadow(color: provider.accent.opacity(0.4), radius: 3)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .simultaneousGesture(providerDragGesture(for: provider))
                        }
                    }
                    if let integrationMessage {
                        Text(integrationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .animation(.easeInOut(duration: 0.18), value: providerOrderRaw)
                .animation(.easeOut(duration: 0.12), value: dropTargetProvider)
                .onPreferenceChange(ProviderCardFramePreferenceKey.self) {
                    providerCardFrames = $0
                }
            }
            .coordinateSpace(name: "providerList")

            Divider()
            footer
        }
        .frame(width: 370, height: 610)
        .appTheme(selectedTheme, systemColorScheme: systemColorScheme)
        .appLanguage(selectedLanguage)
    }

    private func providerDragGesture(for provider: ProviderID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("providerList"))
            .onChanged { value in
                if draggedProvider == nil {
                    draggedProvider = provider
                    dragReferenceFrames = providerCardFrames
                }
                guard draggedProvider == provider else { return }

                dragTranslation = value.translation
                dropTargetProvider = nearestDropTarget(
                    to: value.location.y,
                    excluding: provider
                )
            }
            .onEnded { _ in
                guard draggedProvider == provider else { return }
                if let destination = dropTargetProvider {
                    let currentOrder = ProviderID.orderedProviders(from: providerOrderRaw)
                    let reordered = ProviderID.moving(
                        provider,
                        toPositionOf: destination,
                        in: currentOrder
                    )
                    providerOrderRaw = ProviderID.orderRawValue(for: reordered)
                }

                withAnimation(.easeOut(duration: 0.16)) {
                    draggedProvider = nil
                    dropTargetProvider = nil
                    dragTranslation = .zero
                    dragReferenceFrames = [:]
                }
            }
    }

    private func nearestDropTarget(to pointerY: CGFloat, excluding provider: ProviderID) -> ProviderID? {
        let frames = dragReferenceFrames.isEmpty ? providerCardFrames : dragReferenceFrames
        guard let sourceFrame = frames[provider],
              pointerY < sourceFrame.minY || pointerY > sourceFrame.maxY else {
            return nil
        }

        return displayedProviders
            .filter { $0 != provider && frames[$0] != nil }
            .min { lhs, rhs in
                abs((frames[lhs]?.midY ?? pointerY) - pointerY)
                    < abs((frames[rhs]?.midY ?? pointerY) - pointerY)
            }
    }

    @ViewBuilder
    private func providerCard(for provider: ProviderID) -> some View {
        let snapshot = store.snapshot(for: provider)
        if provider == .claudeCode, case .integrationNotInstalled = snapshot.availability {
            ProviderCard(
                snapshot: snapshot,
                actionTitle: L10n.text("安装 Claude Code 用量集成", "Install Claude Code usage integration"),
                action: installClaudeIntegration,
                showsDragHandle: true
            )
        } else {
            ProviderCard(snapshot: snapshot, showsDragHandle: true)
        }
    }

    private var noProvidersSelected: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist.unchecked")
                .font(.title2)
            Text(L10n.text("尚未选择用量模型", "No usage models selected"))
                .font(.headline)
            Text(L10n.text("请在设置的“显示用量”中勾选模型。", "Select models under Usage Models in Settings."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func installClaudeIntegration() {
        do {
            try ClaudeIntegrationManager.install()
            integrationMessage = L10n.text(
                "安装成功。请在 Claude Code 中完成一次对话，用量将在下一次刷新时出现。",
                "Installed. Complete one Claude Code conversation; usage will appear after the next refresh."
            )
            Task { await store.refresh() }
        } catch {
            integrationMessage = L10n.text("安装失败：", "Installation failed: ") + error.localizedDescription
        }
    }

    private var header: some View {
        HStack {
            Text("AI Usage")
                .font(.title3.weight(.semibold))
            Spacer()
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else if let lastRefresh = store.lastRefresh {
                Label(UsageFormatting.updatedDescription(lastRefresh), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            footerButton(L10n.text("刷新", "Refresh"), icon: "arrow.clockwise") {
                Task { await store.refresh() }
            }
            footerButton(L10n.text("历史", "History"), icon: "clock") {
                showHistoryWindow()
            }
            settingsControl

            Menu {
                Button(L10n.text("退出 AI Usage", "Quit AI Usage")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func showHistoryWindow() {
        if focusExistingHistoryWindow() {
            return
        }

        openWindow(id: "history")

        // The Window scene is created asynchronously on its first opening.
        // Focus it twice so both fast and slower systems reliably bring it forward.
        DispatchQueue.main.async {
            _ = focusExistingHistoryWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            _ = focusExistingHistoryWindow()
        }
    }

    @discardableResult
    private func focusExistingHistoryWindow() -> Bool {
        let historyTitles = Set(["使用历史", "Usage History"])
        guard let historyWindow = NSApp.windows.first(where: { window in
            window.identifier?.rawValue == "history"
                || historyTitles.contains(window.title)
        }) else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        if historyWindow.isMiniaturized {
            historyWindow.deminiaturize(nil)
        }
        historyWindow.makeKeyAndOrderFront(nil)
        historyWindow.orderFrontRegardless()
        return true
    }

    private func footerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            footerLabel(title, icon: icon)
        }
    }

    @ViewBuilder
    private var settingsControl: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                footerLabel(L10n.text("设置", "Settings"), icon: "gearshape")
            }
            .simultaneousGesture(TapGesture().onEnded {
                bringSettingsWindowToFront()
            })
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                bringSettingsWindowToFront()
            } label: {
                footerLabel(L10n.text("设置", "Settings"), icon: "gearshape")
            }
        }
    }

    private func bringSettingsWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        focusExistingSettingsWindow()

        // On the first click SettingsLink creates its window asynchronously.
        // Run a second focus pass after the scene has had time to materialize.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSApp.activate(ignoringOtherApps: true)
            focusExistingSettingsWindow()
        }
    }

    private func focusExistingSettingsWindow() {
        let historyTitles = Set(["使用历史", "Usage History"])
        let settingsWindow = NSApp.windows.first { window in
            window.isVisible
                && window.canBecomeKey
                && window.styleMask.contains(.titled)
                && !historyTitles.contains(window.title)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    private func footerLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage("menubar.display") private var displayMode = MenuBarDisplayMode.highestUsage.rawValue
    @AppStorage(ProviderID.selectionStorageKey) private var selectedProvidersRaw = ProviderID.defaultSelectionRawValue
    @AppStorage(ProviderID.orderStorageKey) private var providerOrderRaw = ProviderID.defaultOrderRawValue
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.simplifiedChinese.rawValue

    private var selectedProviders: Set<ProviderID> {
        ProviderID.selectedProviders(from: selectedProvidersRaw)
    }

    private var menuBarProviders: [ProviderID] {
        ProviderID.menuBarProviders(
            orderRawValue: providerOrderRaw,
            selectedProviders: selectedProviders
        )
    }

    private var menuBarProviderSet: Set<ProviderID> {
        Set(menuBarProviders)
    }

    private var allModelsImage: NSImage? {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let items = menuBarProviders.compactMap { provider -> MenuBarImageItem? in
            guard let logo = NSImage(named: NSImage.Name(provider.logoAssetName)) else { return nil }
            let snapshot = store.snapshot(for: provider)
            let usage = snapshot.windows.first?.usedPercentage
            let stalePrefix = snapshot.availability.isStale ? "~" : ""
            let text = usage.map { "\(stalePrefix)\(Int($0.rounded()))%" }
                ?? snapshot.todayTokens.map { UsageFormatting.compactNumber($0.total) }
                ?? "—"
            return MenuBarImageItem(
                logo: logo,
                text: text,
                textSize: (text as NSString).size(withAttributes: attributes)
            )
        }
        guard !items.isEmpty else { return nil }

        let iconSize: CGFloat = 13
        let iconTextSpacing: CGFloat = 2
        let modelSpacing: CGFloat = 7
        let height: CGFloat = 14
        let width = items.enumerated().reduce(CGFloat.zero) { total, item in
            total + (item.offset == 0 ? 0 : modelSpacing)
                + iconSize + iconTextSpacing + item.element.textSize.width
        }

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (index, item) in items.enumerated() {
                if index > 0 { x += modelSpacing }
                item.logo.draw(
                    in: NSRect(x: x, y: (height - iconSize) / 2, width: iconSize, height: iconSize),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                x += iconSize + iconTextSpacing
                (item.text as NSString).draw(
                    at: NSPoint(x: x, y: (height - item.textSize.height) / 2),
                    withAttributes: attributes
                )
                x += item.textSize.width
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    var body: some View {
        let mode = MenuBarDisplayMode(rawValue: displayMode) ?? .highestUsage
        Group {
            if mode == .bothProviders, !menuBarProviders.isEmpty {
                if let image = allModelsImage {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .fixedSize()
                } else {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                    if let title = store.menuBarTitle(mode: mode, selectedProviders: menuBarProviderSet) {
                        Text(title)
                            .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("AI Usage 用量", "AI Usage"))
    }
}

private struct MenuBarImageItem {
    let logo: NSImage
    let text: String
    let textSize: NSSize
}

private struct ProviderCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ProviderID: CGRect] = [:]

    static func reduce(
        value: inout [ProviderID: CGRect],
        nextValue: () -> [ProviderID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
