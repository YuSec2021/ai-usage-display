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
    private let defaults: UserDefaults
    private let claudeModificationDate: () -> Date?
    private var pendingProviders: Set<ProviderID> = []
    private var refreshGeneration = 0
    private var refreshTask: Task<Void, Never>?
    private var claudeSnapshotMonitorTask: Task<Void, Never>?
    private var lastClaudeDataModificationDate: Date?

    init(
        codexProvider: any UsageProvider = CodexUsageProvider(rateLimitReader: { await CodexRateLimitClient().read() }),
        claudeProvider: any UsageProvider = ClaudeUsageProvider(),
        kimiProvider: any UsageProvider = KimiUsageProvider(),
        miniMaxProvider: any UsageProvider = MiniMaxUsageProvider(),
        defaults: UserDefaults = .standard,
        startsAutomatically: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
        claudeModificationDate: @escaping () -> Date? = {
            [
                ProviderPaths.applicationSupport.appendingPathComponent("claude-snapshot.json"),
                ProviderPaths.claudeDesktopUsageHistory
            ].compactMap {
                try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }.max()
        }
    ) {
        self.providers = [
            .codex: codexProvider,
            .claudeCode: claudeProvider,
            .kimiCode: kimiProvider,
            .miniMax: miniMaxProvider
        ]
        self.defaults = defaults
        self.claudeModificationDate = claudeModificationDate
        // The XCTest host also constructs the app scene. Do not scan the user's
        // real CLI history while isolated provider tests are running.
        if startsAutomatically {
            migrateProviderSelectionForMiniMax()
            start()
        }
    }

    private func migrateProviderSelectionForMiniMax() {
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
        lastClaudeDataModificationDate = claudeModificationDate()
        refreshTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                let storedInterval = self?.defaults.integer(forKey: "refresh.interval") ?? 0
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
        refreshGeneration += 1
        pendingProviders.removeAll()
        isRefreshing = false
        refreshTask?.cancel()
        refreshTask = nil
        claudeSnapshotMonitorTask?.cancel()
        claudeSnapshotMonitorTask = nil
    }

    func restart() {
        stop()
        start()
    }

    func refresh(providers requested: Set<ProviderID> = Set(ProviderID.allCases)) async {
        pendingProviders.formUnion(requested)
        clearDeselectedProviders()
        guard !isRefreshing else { return }
        isRefreshing = true
        let generation = refreshGeneration
        defer {
            if generation == refreshGeneration { isRefreshing = false }
        }

        while !pendingProviders.isEmpty, generation == refreshGeneration, !Task.isCancelled {
            let active = pendingProviders.intersection(selectedProviders)
            pendingProviders.removeAll()

            await withTaskGroup(of: ProviderResult.self) { group in
                for id in active {
                    if let provider = providers[id] { group.addTask { await provider.load() } }
                }

                for await result in group {
                    let id = result.snapshot.provider
                    guard generation == refreshGeneration, !Task.isCancelled,
                          selectedProviders.contains(id), !pendingProviders.contains(id) else { continue }
                    apply(result)
                }
            }
            if generation == refreshGeneration { clearDeselectedProviders() }
        }
    }

    private var selectedProviders: Set<ProviderID> {
        ProviderID.selectedProviders(from: defaults.string(forKey: ProviderID.selectionStorageKey)
            ?? ProviderID.defaultSelectionRawValue)
    }

    private func clearDeselectedProviders() {
        for provider in ProviderID.allCases where !selectedProviders.contains(provider) {
            snapshots[provider] = .empty(provider, availability: .waitingForFirstSample)
            history.removeAll { $0.provider == provider }
        }
    }

    private func apply(_ result: ProviderResult) {
        let id = result.snapshot.provider
        snapshots[id] = result.snapshot
        history.removeAll { $0.provider == id }
        history.append(contentsOf: result.dailyUsage)
        history.sort { $0.date < $1.date }
        lastRefresh = Date()
    }

    func refreshClaudeIfSnapshotChanged() async {
        guard !isRefreshing,
              selectedProviders.contains(.claudeCode),
              let modifiedAt = claudeModificationDate(),
              modifiedAt != lastClaudeDataModificationDate else { return }

        let generation = refreshGeneration
        await refresh(providers: [.claudeCode])
        if generation == refreshGeneration { lastClaudeDataModificationDate = modifiedAt }
    }

    func snapshot(for provider: ProviderID) -> UsageSnapshot {
        snapshots[provider] ?? .empty(provider, availability: .waitingForFirstSample)
    }
}
