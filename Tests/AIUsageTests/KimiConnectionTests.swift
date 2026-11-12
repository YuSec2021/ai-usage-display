import XCTest
@testable import AIUsage

@MainActor
final class KimiConnectionTests: XCTestCase {
    private final class Credentials {
        var key: String? = "old"
        var fails = false
    }

    private func model(_ keys: Credentials, _ requests: VerificationRequests) -> KimiConnectionModel {
        KimiConnectionModel(readKey: { keys.key }, writeKey: {
            if keys.fails { throw APIKeyCredentialError.emptyKey }
            keys.key = $0
        }, deleteKey: {
            if keys.fails { throw APIKeyCredentialError.emptyKey }
            keys.key = nil
        }, loader: { await requests.load($0) })
    }

    func testRemovedKeyCannotBecomeConnectedAfterOldResponse() async throws {
        let keys = Credentials(), requests = VerificationRequests()
        let model = model(keys, requests)
        let task = Task { await model.verify() }
        try await requests.waitForCount(1)
        XCTAssertTrue(model.remove())
        await requests.complete(1, success: true)
        let accepted = await task.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(model.state, .unconfigured)
        XCTAssertFalse(model.isConfigured)
        XCTAssertFalse(model.isVerified)
        XCTAssertNil(keys.key)
    }

    func testChangedKeyAndReverseResponsesKeepNewestVerification() async throws {
        let keys = Credentials(), requests = VerificationRequests()
        let model = model(keys, requests)
        let old = Task { await model.verify() }
        try await requests.waitForCount(1)
        XCTAssertTrue(model.save("new"))
        let new = Task { await model.verify() }
        try await requests.waitForCount(2)
        await requests.complete(2, success: true)
        _ = await new.value
        await requests.complete(1, success: false)
        _ = await old.value
        XCTAssertEqual(model.state, .connected)
        XCTAssertNil(model.message)
        let captured = await requests.keys
        XCTAssertEqual(captured, ["old", "new"])
    }

    func testSameKeyReverseResponsesAndRetryClearOldError() async throws {
        let keys = Credentials(), requests = VerificationRequests()
        let model = model(keys, requests)
        let failed = Task { await model.verify() }
        try await requests.waitForCount(1)
        await requests.complete(1, success: false)
        _ = await failed.value
        XCTAssertEqual(model.state, .failed)
        XCTAssertNotNil(model.message)
        let old = Task { await model.verify() }
        try await requests.waitForCount(2)
        let new = Task { await model.verify() }
        try await requests.waitForCount(3)
        await requests.complete(3, success: true)
        _ = await new.value
        await requests.complete(2, success: false)
        _ = await old.value
        XCTAssertEqual(model.state, .connected)
        XCTAssertNil(model.message)
    }

    func testFailedCredentialWritesKeepExistingConfiguration() async {
        let keys = Credentials(), requests = VerificationRequests()
        let model = model(keys, requests)
        model.synchronize()
        keys.fails = true
        XCTAssertFalse(model.save("new"))
        XCTAssertEqual(keys.key, "old")
        XCTAssertEqual(model.state, .configured)
        XCTAssertFalse(model.remove())
        XCTAssertEqual(keys.key, "old")
        XCTAssertTrue(model.isConfigured)
        keys.fails = false
        XCTAssertTrue(model.remove())
        XCTAssertFalse(model.isVerified)
        XCTAssertFalse(model.isConfigured)
    }
}

private actor VerificationRequests {
    private(set) var keys: [String] = []
    private var continuations: [Int: CheckedContinuation<KimiRateLimitSample?, Never>] = [:]
    func load(_ key: String) async -> KimiRateLimitSample? {
        keys.append(key)
        let id = keys.count
        return await withCheckedContinuation { continuations[id] = $0 }
    }
    func waitForCount(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while keys.count < count, ContinuousClock.now < deadline { await Task.yield() }
        if keys.count < count { throw CocoaError(.fileReadUnknown) }
    }
    func complete(_ id: Int, success: Bool) {
        continuations.removeValue(forKey: id)?.resume(returning: success
            ? KimiRateLimitSample(fiveHour: nil, weekly: nil, observedAt: Date()) : nil)
    }
}
