import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots = Dictionary(
        uniqueKeysWithValues: ProviderID.allCases.map {
            ($0, UsageSnapshot.empty($0, availability: .waitingForFirstSample))
        }
    )
    @Published private(set) var history: [DailyUsage] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private let providers: [ProviderID: any UsageProvider]
    private var refreshTask: Task<Void, Never>?
    private var claudeSnapshotMonitorTask: Task<Void, Never>?
    private var lastClaudeDataModificationDate: Date?

    init(
        codexProvider: any UsageProvider = CodexUsageProvider(),
        claudeProvider: any UsageProvider = ClaudeUsageProvider(),
        kimiProvider: any UsageProvider = KimiUsageProvider(),
        miniMaxProvider: any UsageProvider = MiniMaxUsageProvider()
    ) {
        self.providers = [
            .codex: codexProvider,
            .claudeCode: claudeProvider,
            .kimiCode: kimiProvider,
            .miniMax: miniMaxProvider
        ]
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            migrateProviderSelectionForMiniMax()
        }
        // The XCTest host also constructs the app scene. Do not scan the user's
        // real CLI history while isolated provider tests are running.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            start()
        }
    }

    private func migrateProviderSelectionForMiniMax() {
        let defaults = UserDefaults.standard
        let migrationKey = "providers.selection.migrated.minimax"
        guard !defaults.bool(forKey: migrationKey) else { return }
        defer { defaults.set(true, forKey: migrationKey) }

        let previousDefault = [
            ProviderID.codex.rawValue,
            ProviderID.claudeCode.rawValue,
            ProviderID.kimiCode.rawValue
        ].joined(separator: ",")
        if defaults.string(forKey: ProviderID.selectionStorageKey) == previousDefault {
            defaults.set(
                ProviderID.defaultSelectionRawValue,
                forKey: ProviderID.selectionStorageKey
            )
        }
    }

    func start() {
        guard refreshTask == nil else { return }
        lastClaudeDataModificationDate = claudeDataModificationDate
        refreshTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                let storedInterval = UserDefaults.standard.integer(forKey: "refresh.interval")
                let seconds = storedInterval == 0 ? 30 : max(storedInterval, 15)
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
        claudeSnapshotMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await self?.refreshClaudeIfSnapshotChanged()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        claudeSnapshotMonitorTask?.cancel()
        claudeSnapshotMonitorTask = nil
    }

    func restart() {
        stop()
        start()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let selectedProviders = ProviderID.selectedProviders(
            from: UserDefaults.standard.string(forKey: ProviderID.selectionStorageKey)
                ?? ProviderID.defaultSelectionRawValue
        )
        let activeProviders = providers.filter { selectedProviders.contains($0.key) }

        for provider in ProviderID.allCases where !selectedProviders.contains(provider) {
            snapshots[provider] = .empty(provider, availability: .waitingForFirstSample)
            history.removeAll { $0.provider == provider }
        }

        await withTaskGroup(of: ProviderResult.self) { group in
            for provider in activeProviders.values {
                group.addTask { await provider.load() }
            }

            for await result in group {
                let provider = result.snapshot.provider
                snapshots[provider] = result.snapshot
                history.removeAll { $0.provider == provider }
                history.append(contentsOf: result.dailyUsage)
                history.sort { $0.date < $1.date }
                lastRefresh = Date()
            }
        }
        isRefreshing = false
    }

    private var claudeDataModificationDate: Date? {
        let urls = [
            ProviderPaths.applicationSupport.appendingPathComponent("claude-snapshot.json"),
            ProviderPaths.claudeDesktopUsageHistory
        ]
        return urls.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()
    }

    private func refreshClaudeIfSnapshotChanged() async {
        guard !isRefreshing,
              ProviderID.selectedProviders(
                from: UserDefaults.standard.string(forKey: ProviderID.selectionStorageKey)
                    ?? ProviderID.defaultSelectionRawValue
              ).contains(.claudeCode),
              let modifiedAt = claudeDataModificationDate,
              modifiedAt != lastClaudeDataModificationDate else { return }

        await refresh()
        lastClaudeDataModificationDate = modifiedAt
    }

    func snapshot(for provider: ProviderID) -> UsageSnapshot {
        snapshots[provider] ?? .empty(provider, availability: .waitingForFirstSample)
    }

    func highestUsage(for providers: Set<ProviderID>) -> Int? {
        providers
            .compactMap { snapshots[$0] }
            .filter { $0.availability.isReady }
            .flatMap(\.windows)
            .map { Int($0.usedPercentage.rounded()) }
            .max()
    }

    func menuBarTitle(mode: MenuBarDisplayMode, selectedProviders: Set<ProviderID>) -> String? {
        switch mode {
        case .iconOnly:
            return nil
        case .highestUsage:
            return highestUsage(for: selectedProviders).map { "\($0)%" }
        case .bothProviders:
            return nil
        }
    }
}
