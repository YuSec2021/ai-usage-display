import XCTest
@testable import AIUsage

final class ProviderTests: XCTestCase {
    func testCodexParsesRateLimitsAndSessionDelta() async throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let now = ISO8601DateFormatter().string(from: Date())
        let reset = Date().addingTimeInterval(3_600).timeIntervalSince1970
        let lines = [
            codexLine(timestamp: now, input: 100, cached: 20, output: 10, shortPercent: 42, reset: reset),
            codexLine(timestamp: now, input: 160, cached: 30, output: 25, shortPercent: 43, reset: reset)
        ].joined(separator: "\n")
        try lines.write(to: sessions.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(rootDirectory: root)
        let result = await provider.load()

        XCTAssertTrue(result.snapshot.availability.isReady)
        XCTAssertEqual(result.snapshot.windows.first?.usedPercentage, 43)
        XCTAssertEqual(result.snapshot.windows.first?.label, "5 小时")
        XCTAssertEqual(result.snapshot.todayTokens?.input, 160)
        XCTAssertEqual(result.snapshot.todayTokens?.cachedInput, 30)
        XCTAssertEqual(result.snapshot.todayTokens?.output, 25)

        // An unchanged refresh must reuse the parsed state without double-counting.
        let cachedResult = await provider.load()
        XCTAssertEqual(cachedResult.snapshot.todayTokens, result.snapshot.todayTokens)
    }

    func testClaudeParsesStatusSnapshotAndTranscriptUsage() async throws {
        let claudeRoot = try makeTemporaryDirectory()
        let projects = claudeRoot.appendingPathComponent("projects/sample", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let metrics = claudeRoot.appendingPathComponent("metrics", isDirectory: true)
        try FileManager.default.createDirectory(at: metrics, withIntermediateDirectories: true)
        let support = try makeTemporaryDirectory()
        let snapshotURL = support.appendingPathComponent("claude-snapshot.json")
        let now = Date()
        let snapshot = """
        {"collected_at":\(now.timeIntervalSince1970),"rate_limits":{"five_hour":{"used_percentage":74,"resets_at":\(now.addingTimeInterval(2800).timeIntervalSince1970)},"seven_day":{"used_percentage":43,"resets_at":\(now.addingTimeInterval(80000).timeIntervalSince1970)}},"cost":{"total_cost_usd":1.25}}
        """
        try snapshot.write(to: snapshotURL, atomically: true, encoding: .utf8)

        let timestamp = ISO8601DateFormatter().string(from: now)
        let transcript = """
        {"timestamp":"\(timestamp)","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}}
        {"timestamp":"\(timestamp)","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}}
        {"timestamp":"\(timestamp)","message":{"id":"m2","usage":{"input_tokens":50,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":5}}}
        """
        try transcript.write(to: projects.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        // A stale metrics file with zero counts must not mask transcript usage.
        let staleMetric = """
        {"timestamp":"\(timestamp)","input_tokens":0,"output_tokens":0}
        """
        try staleMetric.write(
            to: metrics.appendingPathComponent("costs.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let provider = ClaudeUsageProvider(
            claudeDirectory: claudeRoot,
            snapshotURL: snapshotURL,
            planUsageURL: support.appendingPathComponent("missing-plan-usage.json")
        )
        let result = await provider.load()

        XCTAssertTrue(result.snapshot.availability.isReady)
        XCTAssertEqual(result.snapshot.windows.map(\.usedPercentage), [74, 43])
        XCTAssertEqual(result.snapshot.todayTokens?.input, 150)
        XCTAssertEqual(result.snapshot.todayTokens?.cachedInput, 75)
        XCTAssertEqual(result.snapshot.todayTokens?.output, 30)
        XCTAssertEqual(result.snapshot.estimatedCostUSD, Decimal(string: "1.25"))

        let updatedTranscript = transcript + """

        {"timestamp":"\(timestamp)","message":{"id":"m3","usage":{"input_tokens":25,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":10}}}
        """
        try updatedTranscript.write(
            to: projects.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let updatedResult = await provider.load()
        XCTAssertEqual(updatedResult.snapshot.todayTokens?.input, 175)
        XCTAssertEqual(updatedResult.snapshot.todayTokens?.cachedInput, 85)
        XCTAssertEqual(updatedResult.snapshot.todayTokens?.output, 35)
    }

    func testMissingDirectoriesReportCLIUnavailable() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codex = await CodexUsageProvider(rootDirectory: missing).load()
        let claude = await ClaudeUsageProvider(
            claudeDirectory: missing,
            snapshotURL: missing.appendingPathComponent("snapshot"),
            planUsageURL: missing.appendingPathComponent("plan-usage")
        ).load()
        XCTAssertEqual(codex.snapshot.availability, .cliNotInstalled)
        XCTAssertEqual(claude.snapshot.availability, .cliNotInstalled)
    }

    func testClaudeMarksOldRateLimitSnapshotAsStale() async throws {
        let claudeRoot = try makeTemporaryDirectory()
        let support = try makeTemporaryDirectory()
        let snapshotURL = support.appendingPathComponent("claude-snapshot.json")
        let collectedAt = Date().addingTimeInterval(-600)
        let snapshot = """
        {"collected_at":\(collectedAt.timeIntervalSince1970),"rate_limits":{"five_hour":{"used_percentage":1}}}
        """
        try snapshot.write(to: snapshotURL, atomically: true, encoding: .utf8)

        let result = await ClaudeUsageProvider(
            claudeDirectory: claudeRoot,
            snapshotURL: snapshotURL,
            planUsageURL: support.appendingPathComponent("missing-plan-usage.json")
        ).load()

        XCTAssertTrue(result.snapshot.availability.isStale)
        XCTAssertEqual(result.snapshot.windows.first?.usedPercentage, 1)
    }

    func testClaudeDesktopUsageOverridesOlderCLIStatusSnapshot() async throws {
        let claudeRoot = try makeTemporaryDirectory()
        let support = try makeTemporaryDirectory()
        let snapshotURL = support.appendingPathComponent("claude-snapshot.json")
        let planUsageURL = support.appendingPathComponent("plan-usage-history.json")
        let oldTimestamp = Date().addingTimeInterval(-600).timeIntervalSince1970
        try """
        {"collected_at":\(oldTimestamp),"rate_limits":{"five_hour":{"used_percentage":1},"seven_day":{"used_percentage":5}}}
        """.write(to: snapshotURL, atomically: true, encoding: .utf8)

        let currentMilliseconds = Date().timeIntervalSince1970 * 1_000
        try """
        {"version":2,"samples":[{"t":\(currentMilliseconds),"org":"test","u":{"fh":6,"sd":7}}]}
        """.write(to: planUsageURL, atomically: true, encoding: .utf8)

        let result = await ClaudeUsageProvider(
            claudeDirectory: claudeRoot,
            snapshotURL: snapshotURL,
            planUsageURL: planUsageURL
        ).load()

        XCTAssertEqual(result.snapshot.windows.map(\.usedPercentage), [6, 7])
        XCTAssertTrue(result.snapshot.availability.isReady)
    }

    private func codexLine(timestamp: String, input: Int, cached: Int, output: Int, shortPercent: Double, reset: TimeInterval) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":2}},"rate_limits":{"primary":{"used_percent":\(shortPercent),"resets_at":\(reset),"window_minutes":300},"secondary":{"used_percent":20,"resets_at":\(reset + 50000),"window_minutes":10080}}}}
        """
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AIUsageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
