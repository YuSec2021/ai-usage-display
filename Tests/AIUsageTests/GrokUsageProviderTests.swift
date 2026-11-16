import XCTest
@testable import AIUsage

final class GrokUsageProviderTests: XCTestCase {
    private static let accountName = "onqw4zbomnwgszlooqxhg3djmnss4y3mnfsw45bnnvsxiyjomfrwg33vnz2c243mn52a.blob"
    private static let quotaA = "onqw4zbomnwgszlooqxhg3djmnss4yldmnxxk3tufztxe33leu3ugztjpb2hk4tffvqs453fmvvwy6jnovzwcz3ffzrwcy3imu.blob"
    private static let quotaB = "onqw4zbomnwgszlooqxhg3djmnss4yldmnxxk3tufztxe33leu3ugztjpb2hk4tffvrc453fmvvwy6jnovzwcz3ffzrwcy3imu.blob"
    private static let longQuota = "luyvwpsrfhj73pdqyomxyyptyck5glreuckutqwymlnt534g6fwq.kblob"
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func account(_ value: String? = "grok|fixture-a", in root: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "value": value as Any? ?? NSNull()])
        try data.write(to: root.appendingPathComponent(Self.accountName), options: .atomic)
    }

    private func quota(
        in root: URL, used: Double = 12.5, reset: Date? = nil,
        readAt: Date? = nil, expires: Date? = nil, schema: Int = 3,
        hasLimit: Bool = true, team: Int? = nil, kind: String = "present",
        name: String = GrokUsageProviderTests.quotaA
    ) throws {
        let usage: [String: Any] = [
            "percentUsed": used, "nextResetMs": (reset ?? date.addingTimeInterval(3_600)).timeIntervalSince1970 * 1_000,
            "hasNonZeroIncludedLimit": hasLimit, "isTeamSeat": team != nil,
            "readForTeamId": team as Any? ?? NSNull(),
            "ignored": "fixture-only-field"
        ]
        let value: [String: Any] = [
            "kind": kind, "selectedTeamId": team as Any? ?? NSNull(),
            "reading": ["usage": usage, "readAtMs": (readAt ?? date).timeIntervalSince1970 * 1_000],
            "expiresAtMs": (expires ?? date.addingTimeInterval(86_400)).timeIntervalSince1970 * 1_000
        ]
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": schema, "value": value])
        try data.write(to: root.appendingPathComponent(name), options: .atomic)
    }

    func testZeroPartialFullAndOverLimitProduceOnlyWeeklyQuota() async throws {
        let root = try directory()
        try account(in: root)
        let now = date
        let provider = GrokUsageProvider(rootDirectory: root, now: { now })
        for used in [0.0, 12.5, 100.0, 125.0] {
            try quota(in: root, used: used)
            let result = await provider.load()
            XCTAssertTrue(result.snapshot.availability.isReady)
            XCTAssertEqual(result.snapshot.provider, .grok)
            XCTAssertEqual(result.snapshot.primaryQuotaWindow(at: now)?.usedPercentage, min(used, 100))
            XCTAssertEqual(result.snapshot.windows.first?.durationMinutes, 10_080)
            XCTAssertNil(result.snapshot.fiveHourWindow(at: now))
            XCTAssertNil(result.snapshot.todayTokens)
            XCTAssertTrue(result.dailyUsage.isEmpty)
        }
    }

    func testAgingExpiryAndServerResetNeverInventANewWindow() async throws {
        let root = try directory()
        try account(in: root)
        try quota(in: root, reset: date.addingTimeInterval(1_000))
        let clock = GrokTestClock(date)
        let provider = GrokUsageProvider(rootDirectory: root, now: { clock.date })
        clock.date = date.addingTimeInterval(300)
        var result = await provider.load()
        XCTAssertTrue(result.snapshot.availability.isReady)
        clock.date = date.addingTimeInterval(301)
        result = await provider.load()
        XCTAssertTrue(result.snapshot.availability.isStale)
        XCTAssertEqual(result.snapshot.windows.count, 1)
        clock.date = date.addingTimeInterval(1_000)
        result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        XCTAssertTrue(result.snapshot.availability.isStale)

        clock.date = date
        try quota(in: root, reset: date.addingTimeInterval(200_000), expires: date.addingTimeInterval(500))
        clock.date = date.addingTimeInterval(500)
        result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        try quota(in: root, reset: date.addingTimeInterval(200_000), expires: date.addingTimeInterval(300_000))
        clock.date = date.addingTimeInterval(86_400)
        result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
    }

    func testMalformedSameAccountCacheKeepsValidOldValueButNotPastExpiry() async throws {
        let root = try directory()
        try account(in: root)
        try quota(in: root, expires: date.addingTimeInterval(30))
        let clock = GrokTestClock(date)
        let provider = GrokUsageProvider(rootDirectory: root, now: { clock.date })
        _ = await provider.load()
        try Data("{\"schemaVersion\":".utf8).write(to: root.appendingPathComponent(Self.quotaA))
        var result = await provider.load()
        XCTAssertTrue(result.snapshot.availability.isStale)
        XCTAssertEqual(result.snapshot.windows.first?.usedPercentage, 12.5)
        clock.date = date.addingTimeInterval(30)
        result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
    }

    func testAccountSwitchAndLogoutDoNotReusePreviousAccount() async throws {
        let root = try directory()
        try account(in: root)
        try quota(in: root, used: 88)
        let now = date
        let provider = GrokUsageProvider(rootDirectory: root, now: { now })
        _ = await provider.load()
        try account("grok|fixture-b", in: root)
        var result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        try quota(in: root, used: 3, name: Self.quotaB)
        result = await provider.load()
        XCTAssertEqual(result.snapshot.windows.first?.usedPercentage, 3)
        try account(nil, in: root)
        result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
    }

    func testReadOnlyAccessesRequestedSlicesAndRejectsAccountRace() async throws {
        let root = try directory()
        try account(in: root)
        try quota(in: root)
        let now = date
        let meta = root.appendingPathComponent(Self.accountName)
        let switched = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "value": "grok|fixture-b"])
        let allowed = [Self.accountName, Self.quotaA]
        let provider = GrokUsageProvider(rootDirectory: root, now: { now }, reader: { url, limit in
            guard allowed.contains(url.lastPathComponent) else { throw CocoaError(.fileReadNoPermission) }
            let data = try GrokCacheFile.read(url, limit)
            if url.lastPathComponent == Self.quotaA { try switched.write(to: meta, options: .atomic) }
            return data
        })
        let result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        XCTAssertFalse(result.snapshot.availability.isReady)
    }

    func testRemovedQuotaSliceDoesNotResurrectPersonalUsageAfterTeamChange() async throws {
        let root = try directory()
        try account(in: root)
        try quota(in: root)
        let now = date
        let provider = GrokUsageProvider(rootDirectory: root, now: { now })
        _ = await provider.load()
        try FileManager.default.removeItem(at: root.appendingPathComponent(Self.quotaA))
        let result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        XCTAssertFalse(result.snapshot.availability.hasUsableData)
    }

    func testUnknownSchemaTeamMissingLimitAndNegativeUsageClearOldSamples() async throws {
        let root = try directory()
        try account(in: root)
        let now = date
        let provider = GrokUsageProvider(rootDirectory: root, now: { now })
        for scenario in 0..<5 {
            try quota(in: root)
            _ = await provider.load()
            switch scenario {
            case 0: try quota(in: root, schema: 4)
            case 1: try quota(in: root, team: 42)
            case 2: try quota(in: root, hasLimit: false)
            case 3: try quota(in: root, used: -1)
            default: try quota(in: root, kind: "absent")
            }
            let result = await provider.load()
            XCTAssertTrue(result.snapshot.windows.isEmpty)
            XCTAssertFalse(result.snapshot.availability.hasUsableData)
        }
    }

    func testUnknownResetRemainsUnknownAndFutureObservationIsRejected() async throws {
        let root = try directory()
        try account(in: root)
        try quota(in: root)
        let path = root.appendingPathComponent(Self.quotaA)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        var cache = try XCTUnwrap(envelope["value"] as? [String: Any])
        var reading = try XCTUnwrap(cache["reading"] as? [String: Any])
        var usage = try XCTUnwrap(reading["usage"] as? [String: Any])
        usage["nextResetMs"] = NSNull()
        reading["usage"] = usage
        cache["reading"] = reading
        envelope["value"] = cache
        try JSONSerialization.data(withJSONObject: envelope).write(to: path)
        let now = date
        let provider = GrokUsageProvider(rootDirectory: root, now: { now })
        var result = await provider.load()
        XCTAssertTrue(result.snapshot.availability.isReady)
        XCTAssertNil(result.snapshot.windows.first?.resetsAt)
        try quota(in: root, readAt: now.addingTimeInterval(61))
        result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
    }

    func testMissingOversizedAndSymlinkFilesAreRejected() async throws {
        let root = try directory()
        let now = date
        let provider = GrokUsageProvider(rootDirectory: root, now: { now })
        var result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        try account(in: root)
        let path = root.appendingPathComponent(Self.quotaA)
        try Data(repeating: 32, count: 65_537).write(to: path)
        result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        try FileManager.default.removeItem(at: path)
        let unrelated = root.appendingPathComponent("unrelated.json")
        try Data("{}".utf8).write(to: unrelated)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: unrelated)
        result = await provider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        try FileManager.default.removeItem(at: root)
        result = await provider.load()
        XCTAssertEqual(result.snapshot.availability, .cliNotInstalled)
    }

    func testLongKeysValidateDigestFrameAndShortKeyMatchesIndependentFixture() async throws {
        XCTAssertEqual(GrokCacheFile.fileName(for: GrokCacheFile.accountKey), Self.accountName)
        XCTAssertEqual(GrokCacheFile.fileName(for: GrokCacheFile.quotaKey(account: "grok|fixture-a")), Self.quotaA)
        let root = try directory()
        let slot = "grok|" + String(repeating: "x", count: 200)
        try account(slot, in: root)
        try quota(in: root)
        let body = try Data(contentsOf: root.appendingPathComponent(Self.quotaA))
        let key = "sand.client.slice.account.grok%7C" + String(repeating: "x", count: 200) + ".weekly-usage.cache"
        XCTAssertEqual(GrokCacheFile.fileName(for: key), Self.longQuota)
        var framed = try JSONEncoder().encode(key)
        framed.append(10)
        framed.append(body)
        try framed.write(to: root.appendingPathComponent(Self.longQuota))
        let now = date
        let provider = GrokUsageProvider(rootDirectory: root, now: { now })
        var result = await provider.load()
        XCTAssertEqual(result.snapshot.windows.first?.usedPercentage, 12.5)
        try Data(("\"wrong-key\"\n" + String(decoding: body, as: UTF8.self)).utf8)
            .write(to: root.appendingPathComponent(Self.longQuota))
        let freshProvider = GrokUsageProvider(rootDirectory: root, now: { now })
        result = await freshProvider.load()
        XCTAssertTrue(result.snapshot.windows.isEmpty)
    }
}

private final class GrokTestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}
