import XCTest
@testable import AIUsage

@MainActor
final class UsageStoreTests: XCTestCase {
    private func defaults(_ selected: Set<ProviderID> = Set(ProviderID.allCases)) -> UserDefaults {
        let name = "AIUsageTests.\(UUID().uuidString)"
        let value = UserDefaults(suiteName: name)!
        value.set(ProviderID.selectionRawValue(for: selected), forKey: ProviderID.selectionStorageKey)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return value
    }

    private func store(_ providers: [StoreProvider], defaults: UserDefaults, modified: @escaping () -> Date? = { nil }) -> UsageStore {
        UsageStore(codexProvider: providers[0], claudeProvider: providers[1], kimiProvider: providers[2],
                   miniMaxProvider: providers[3], defaults: defaults, startsAutomatically: false,
                   claudeModificationDate: modified)
    }

    private func waitForCall(_ provider: StoreProvider) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await provider.calls == 0, ContinuousClock.now < deadline { await Task.yield() }
        let calls = await provider.calls
        XCTAssertGreaterThan(calls, 0)
    }

    func testClaudeFileChangeOnlyRefreshesClaudeAndFullRefreshKeepsAllSelected() async {
        let providers = ProviderID.allCases.map { StoreProvider($0) }
        var modified = Date()
        let store = store(providers, defaults: defaults(), modified: { modified })
        await store.refreshClaudeIfSnapshotChanged()
        await store.refreshClaudeIfSnapshotChanged()
        for (index, provider) in providers.enumerated() {
            let count = await provider.calls
            XCTAssertEqual(count, index == 1 ? 1 : 0)
        }
        modified = modified.addingTimeInterval(1)
        await store.refreshClaudeIfSnapshotChanged()
        await store.refresh()
        for (index, provider) in providers.enumerated() {
            let count = await provider.calls
            XCTAssertEqual(count, index == 1 ? 3 : 1)
        }
        XCTAssertFalse(store.isRefreshing)
        XCTAssertNotNil(store.lastRefresh)
        XCTAssertEqual(Set(store.history.map(\.provider)), Set(ProviderID.allCases))
    }

    func testSelectionChangeQueuesNewProviderAndRejectsDeselectedResult() async throws {
        let gate = StoreGate()
        let providers = ProviderID.allCases.map { StoreProvider($0, gate: $0 == .codex ? gate : nil) }
        let preferences = defaults([.codex])
        let store = store(providers, defaults: preferences)
        let first = Task { await store.refresh() }
        try await waitForCall(providers[0])
        preferences.set("claudeCode", forKey: ProviderID.selectionStorageKey)
        await store.refresh()
        await gate.open()
        await first.value
        XCTAssertEqual(store.snapshot(for: .codex).availability, .waitingForFirstSample)
        XCTAssertTrue(store.snapshot(for: .claudeCode).availability.isReady)
        XCTAssertEqual(store.history.map(\.provider), [.claudeCode])
        let count = await providers[1].calls
        XCTAssertEqual(count, 1)
        XCTAssertFalse(store.isRefreshing)
    }

    func testRepeatedRefreshIsQueuedAndUsesNewestResult() async throws {
        let gate = StoreGate()
        let providers = ProviderID.allCases.map { StoreProvider($0, gate: $0 == .codex ? gate : nil) }
        let store = store(providers, defaults: defaults([.codex]))
        let first = Task { await store.refresh() }
        try await waitForCall(providers[0])
        await store.refresh(providers: [.codex])
        await store.refresh(providers: [.codex])
        await gate.open()
        await first.value
        let count = await providers[0].calls
        XCTAssertEqual(count, 2)
        XCTAssertEqual(store.snapshot(for: .codex).todayTokens?.input, 2)
        XCTAssertEqual(store.history.count, 1)
    }

    func testStopInvalidatesOldResultAndAllowsNewRefresh() async throws {
        let gate = StoreGate()
        let providers = ProviderID.allCases.map { StoreProvider($0, gate: $0 == .codex ? gate : nil) }
        let store = store(providers, defaults: defaults([.codex]))
        let first = Task { await store.refresh() }
        try await waitForCall(providers[0])
        store.stop()
        await store.refresh()
        XCTAssertEqual(store.snapshot(for: .codex).todayTokens?.input, 2)
        await gate.open()
        await first.value
        XCTAssertEqual(store.snapshot(for: .codex).todayTokens?.input, 2)
        XCTAssertFalse(store.isRefreshing)
    }
}

private actor StoreGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor StoreProvider: UsageProvider {
    nonisolated let id: ProviderID
    private let gate: StoreGate?
    private(set) var calls = 0
    init(_ id: ProviderID, gate: StoreGate? = nil) { self.id = id; self.gate = gate }
    func load() async -> ProviderResult {
        calls += 1
        let count = calls
        if count == 1 { await gate?.wait() }
        let now = Date()
        let tokens = TokenUsage(input: count, cachedInput: 0, output: 0, reasoningOutput: 0)
        return ProviderResult(snapshot: UsageSnapshot(
            provider: id, windows: [], todayTokens: tokens, estimatedCostUSD: nil,
            observedAt: now, availability: .ready(lastUpdated: now)
        ), dailyUsage: [DailyUsage(date: now, provider: id, tokens: tokens)])
    }
}
