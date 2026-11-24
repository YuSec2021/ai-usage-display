import XCTest
@testable import AIUsage

final class SharedFixtureTests: XCTestCase {
    func testSharedFixturesMatchExpectedOutput() async throws {
        let fixturesRoot = sharedFixturesRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixturesRoot.path),
            "Shared fixtures directory not found at \(fixturesRoot.path)"
        )

        let cases = try discoverFixtureCases(under: fixturesRoot)
        XCTAssertFalse(cases.isEmpty, "No shared fixture cases found under \(fixturesRoot.path)")

        let discoveredProviders = Set(cases.map(\.provider))
        XCTAssertEqual(
            discoveredProviders,
            ["codex", "claude", "kimi"],
            "Expected shared fixtures for codex, claude, and kimi"
        )

        for fixtureCase in cases {
            try await verifyFixtureCase(fixtureCase)
        }
    }

    private func verifyFixtureCase(_ fixtureCase: DiscoveredFixtureCase) async throws {
        let context = "\(fixtureCase.provider)/\(fixtureCase.caseName)"
        let expectedData = try Data(contentsOf: fixtureCase.expectedURL)
        let expected = try JSONDecoder().decode(SharedFixtureExpected.self, from: expectedData)

        XCTAssertEqual(expected.schemaVersion, 1, "[\(context)] Unexpected schemaVersion")
        XCTAssertEqual(expected.provider, fixtureCase.provider, "[\(context)] Provider mismatch with directory")
        XCTAssertEqual(expected.caseName, fixtureCase.caseName, "[\(context)] Case name mismatch with directory")

        let nowDate = try XCTUnwrap(
            ISODateParser.parse(expected.now),
            "[\(context)] Invalid ISO 8601 'now': \(expected.now)"
        )
        let timeZone = try XCTUnwrap(
            TimeZone(identifier: expected.timeZone),
            "[\(context)] Invalid timeZone: \(expected.timeZone)"
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        if let exemptions = expected.platformExemptions {
            for (platform, exemption) in exemptions {
                XCTAssertFalse(
                    exemption.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "[\(context)] platformExemptions.\(platform).reason must be non-empty"
                )
            }
        }

        let macOSExemption = expected.platformExemptions?["macos"]
        let exemptionNote = macOSExemption.map { " (macOS exemption: \($0.reason))" } ?? ""

        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceInputDir = fixtureCase.caseDirectory.appendingPathComponent("input", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sourceInputDir.path),
            "[\(context)] Missing input/ directory at \(sourceInputDir.path)"
        )
        let tempInputDir = tempRoot.appendingPathComponent("input", isDirectory: true)
        try FileManager.default.copyItem(at: sourceInputDir, to: tempInputDir)
        try setModificationDates(under: tempInputDir, to: nowDate)

        let result = try await runProvider(
            provider: expected.provider,
            caseDirectory: fixtureCase.caseDirectory,
            tempRoot: tempRoot,
            inputDirectory: tempInputDir,
            calendar: calendar,
            now: nowDate
        )

        let expectedState = macOSExemption?.state ?? expected.state
        let actualState = canonicalState(result.snapshot.availability)
        XCTAssertEqual(
            actualState,
            expectedState,
            "[\(context)] State mismatch\(exemptionNote)"
        )

        let expectedDaily = (macOSExemption?.dailyUsage ?? expected.dailyUsage)
            .sorted { $0.date < $1.date }
        let actualDaily = normalizeDailyUsage(result.dailyUsage, calendar: calendar, timeZone: timeZone)
        XCTAssertEqual(
            actualDaily,
            expectedDaily,
            "[\(context)] dailyUsage mismatch\(exemptionNote)"
        )

        let expectedWindows = (macOSExemption?.quotaWindows ?? expected.quotaWindows)
            .sorted(by: quotaWindowSort)
        let actualWindows = normalizeQuotaWindows(result.snapshot.windows)
            .sorted(by: quotaWindowSort)

        XCTAssertEqual(
            actualWindows.count,
            expectedWindows.count,
            "[\(context)] quotaWindows count mismatch\(exemptionNote): actual=\(actualWindows), expected=\(expectedWindows)"
        )
        for (index, (actual, target)) in zip(actualWindows, expectedWindows).enumerated() {
            XCTAssertEqual(
                actual.minutes,
                target.minutes,
                "[\(context)] quotaWindows[\(index)].minutes mismatch\(exemptionNote)"
            )
            XCTAssertEqual(
                actual.usedPercent,
                target.usedPercent,
                accuracy: 0.01,
                "[\(context)] quotaWindows[\(index)].usedPercent mismatch\(exemptionNote)"
            )
            try assertResetsAtEqual(
                actual: actual.resetsAt,
                expectedISO: target.resetsAt,
                context: "[\(context)] quotaWindows[\(index)].resetsAt\(exemptionNote)"
            )
        }
    }

    private func runProvider(
        provider: String,
        caseDirectory: URL,
        tempRoot: URL,
        inputDirectory: URL,
        calendar: Calendar,
        now: Date
    ) async throws -> ProviderResult {
        switch provider {
        case "codex":
            let codex = CodexUsageProvider(
                rootDirectory: inputDirectory,
                calendar: calendar,
                rateLimitReader: { nil },
                now: { now }
            )
            return await codex.load()

        case "claude":
            let snapshotURL = tempRoot.appendingPathComponent("claude-snapshot.json")
            let sourceSnapshot = caseDirectory.appendingPathComponent("claude-snapshot.json")
            if FileManager.default.fileExists(atPath: sourceSnapshot.path) {
                try FileManager.default.copyItem(at: sourceSnapshot, to: snapshotURL)
                try FileManager.default.setAttributes(
                    [.modificationDate: now],
                    ofItemAtPath: snapshotURL.path
                )
            }
            let missingPlanUsageURL = tempRoot.appendingPathComponent("missing-plan-usage.json")
            let claude = ClaudeUsageProvider(
                claudeDirectory: inputDirectory,
                snapshotURL: snapshotURL,
                planUsageURL: missingPlanUsageURL,
                calendar: calendar,
                now: { now }
            )
            return await claude.load()

        case "kimi":
            let apiURL = caseDirectory.appendingPathComponent("kimi-usage-api.json")
            let rateLimitLoader: @Sendable () async -> KimiRateLimitSample?
            if FileManager.default.fileExists(atPath: apiURL.path) {
                let apiData = try Data(contentsOf: apiURL)
                rateLimitLoader = { KimiUsageAPI.decode(apiData, observedAt: now) }
            } else {
                rateLimitLoader = { nil }
            }
            let kimi = KimiUsageProvider(
                rootDirectory: inputDirectory,
                desktopLogURLs: [],
                calendar: calendar,
                rateLimitLoader: rateLimitLoader,
                now: { now }
            )
            return await kimi.load()

        default:
            XCTFail("Unsupported shared fixture provider: \(provider)")
            return ProviderResult(
                snapshot: .empty(.codex, availability: .unsupportedFormat),
                dailyUsage: []
            )
        }
    }

    private func sharedFixturesRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/AIUsageTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures/shared", isDirectory: true)
    }

    private func discoverFixtureCases(under root: URL) throws -> [DiscoveredFixtureCase] {
        let fileManager = FileManager.default
        let providerDirs = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var cases: [DiscoveredFixtureCase] = []
        for providerDir in providerDirs {
            let caseDirs = try fileManager.contentsOfDirectory(
                at: providerDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            for caseDir in caseDirs {
                let expectedURL = caseDir.appendingPathComponent("expected.json")
                XCTAssertTrue(
                    fileManager.fileExists(atPath: expectedURL.path),
                    "Missing expected.json in \(caseDir.path)"
                )
                cases.append(DiscoveredFixtureCase(
                    provider: providerDir.lastPathComponent,
                    caseName: caseDir.lastPathComponent,
                    caseDirectory: caseDir,
                    expectedURL: expectedURL
                ))
            }
        }
        return cases
    }

    private func setModificationDates(under directory: URL, to date: Date) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return }

        for case let url as URL in enumerator {
            let isRegularFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            if isRegularFile {
                try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            }
        }
    }

    private func canonicalState(_ availability: ProviderAvailability) -> String {
        switch availability {
        case .ready: "ready"
        case .stale: "stale"
        case .waitingForFirstSample: "waiting"
        case .cliNotInstalled: "missing"
        case .integrationNotInstalled: "integrationRequired"
        case .unsupportedFormat: "unsupportedFormat"
        case .permissionDenied: "permissionDenied"
        case .failed(let message): "failed(\(message))"
        }
    }

    private func normalizeDailyUsage(
        _ dailyUsage: [DailyUsage],
        calendar: Calendar,
        timeZone: TimeZone
    ) -> [ExpectedDailyUsage] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return dailyUsage
            .map { entry in
                ExpectedDailyUsage(
                    date: formatter.string(from: entry.date),
                    tokens: ExpectedTokens(
                        input: entry.tokens.input,
                        cached: entry.tokens.cachedInput,
                        output: entry.tokens.output
                    )
                )
            }
            .sorted { $0.date < $1.date }
    }

    private func normalizeQuotaWindows(_ windows: [RateLimitWindow]) -> [NormalizedQuotaWindow] {
        windows.map { window in
            NormalizedQuotaWindow(
                minutes: window.durationMinutes,
                usedPercent: window.usedPercentage,
                resetsAt: window.resetsAt
            )
        }
    }

    private func quotaWindowSort(_ lhs: ExpectedQuotaWindow, _ rhs: ExpectedQuotaWindow) -> Bool {
        let leftMinutes = lhs.minutes ?? Int.max
        let rightMinutes = rhs.minutes ?? Int.max
        if leftMinutes != rightMinutes { return leftMinutes < rightMinutes }
        return lhs.usedPercent < rhs.usedPercent
    }

    private func quotaWindowSort(_ lhs: NormalizedQuotaWindow, _ rhs: NormalizedQuotaWindow) -> Bool {
        let leftMinutes = lhs.minutes ?? Int.max
        let rightMinutes = rhs.minutes ?? Int.max
        if leftMinutes != rightMinutes { return leftMinutes < rightMinutes }
        return lhs.usedPercent < rhs.usedPercent
    }

    private func assertResetsAtEqual(
        actual: Date?,
        expectedISO: String?,
        context: String
    ) throws {
        guard let expectedISO else {
            XCTAssertNil(actual, "\(context): expected nil, got \(String(describing: actual))")
            return
        }
        let expectedDate = try XCTUnwrap(
            ISODateParser.parse(expectedISO),
            "\(context): invalid ISO 8601 resetsAt '\(expectedISO)'"
        )
        let actualDate = try XCTUnwrap(actual, "\(context): expected \(expectedISO), got nil")
        XCTAssertEqual(
            actualDate.timeIntervalSince(expectedDate),
            0,
            accuracy: 1.0,
            "\(context): expected \(expectedISO), got \(actualDate)"
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIUsageSharedFixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct DiscoveredFixtureCase {
    let provider: String
    let caseName: String
    let caseDirectory: URL
    let expectedURL: URL
}

private struct SharedFixtureExpected: Decodable {
    let schemaVersion: Int
    let provider: String
    let caseName: String
    let description: String
    let now: String
    let timeZone: String
    let dailyUsage: [ExpectedDailyUsage]
    let quotaWindows: [ExpectedQuotaWindow]
    let state: String
    let platformExemptions: [String: PlatformExemption]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case provider
        case caseName = "case"
        case description
        case now
        case timeZone
        case dailyUsage
        case quotaWindows
        case state
        case platformExemptions
    }
}

private struct PlatformExemption: Decodable {
    let reason: String
    let dailyUsage: [ExpectedDailyUsage]?
    let quotaWindows: [ExpectedQuotaWindow]?
    let state: String?
}

private struct ExpectedDailyUsage: Decodable, Equatable {
    let date: String
    let tokens: ExpectedTokens
}

private struct ExpectedTokens: Decodable, Equatable {
    let input: Int
    let cached: Int
    let output: Int
}

private struct ExpectedQuotaWindow: Decodable {
    let minutes: Int?
    let usedPercent: Double
    let resetsAt: String?
}

private struct NormalizedQuotaWindow {
    let minutes: Int?
    let usedPercent: Double
    let resetsAt: Date?
}
