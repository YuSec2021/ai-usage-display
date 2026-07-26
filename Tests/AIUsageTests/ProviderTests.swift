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
        XCTAssertEqual(result.snapshot.todayTokens?.input, 225)
        XCTAssertEqual(result.snapshot.todayTokens?.cachedInput, 75)
        XCTAssertEqual(result.snapshot.todayTokens?.output, 30)
        XCTAssertEqual(result.snapshot.estimatedCostUSD, Decimal(string: "1.25"))
        XCTAssertEqual(result.dailyUsage.count, 1)
        XCTAssertEqual(result.dailyUsage.first?.provider, .claudeCode)
        XCTAssertEqual(result.dailyUsage.first?.tokens.input, 225)
        XCTAssertEqual(result.dailyUsage.first?.tokens.cachedInput, 75)
        XCTAssertEqual(result.dailyUsage.first?.tokens.output, 30)

        let updatedTranscript = transcript + """

        {"timestamp":"\(timestamp)","message":{"id":"m3","usage":{"input_tokens":25,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":10}}}
        """
        try updatedTranscript.write(
            to: projects.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let updatedResult = await provider.load()
        XCTAssertEqual(updatedResult.snapshot.todayTokens?.input, 260)
        XCTAssertEqual(updatedResult.snapshot.todayTokens?.cachedInput, 85)
        XCTAssertEqual(updatedResult.snapshot.todayTokens?.output, 35)
        XCTAssertEqual(updatedResult.dailyUsage.first?.tokens.input, 260)
        XCTAssertEqual(updatedResult.dailyUsage.first?.tokens.cachedInput, 85)
        XCTAssertEqual(updatedResult.dailyUsage.first?.tokens.output, 35)
    }

    func testKimiParsesUsageRecordsAndIncrementalUpdates() async throws {
        let root = try makeTemporaryDirectory()
        let agents = root.appendingPathComponent(
            "sessions/work/session/agents/main",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let wireURL = agents.appendingPathComponent("wire.jsonl")
        let now = Date().timeIntervalSince1970 * 1_000
        let initial = """
        {"type":"context.append_loop_event","time":\(now - 10)}
        {"type":"usage.record","model":"kimi-k2.5","usage":{"inputOther":100,"output":20,"inputCacheRead":30,"inputCacheCreation":10},"usageScope":"turn","time":\(now)}
        """
        try initial.write(to: wireURL, atomically: true, encoding: .utf8)

        let provider = KimiUsageProvider(
            rootDirectory: root,
            desktopLogURLs: [],
            rateLimitLoader: { nil }
        )
        let result = await provider.load()

        XCTAssertTrue(result.snapshot.availability.isReady)
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        XCTAssertEqual(result.snapshot.todayTokens?.input, 140)
        XCTAssertEqual(result.snapshot.todayTokens?.cachedInput, 40)
        XCTAssertEqual(result.snapshot.todayTokens?.output, 20)
        XCTAssertEqual(result.snapshot.todayTokens?.total, 160)
        XCTAssertEqual(result.dailyUsage.first?.provider, .kimiCode)

        let unchanged = await provider.load()
        XCTAssertEqual(unchanged.snapshot.todayTokens, result.snapshot.todayTokens)

        let appended = initial + """

        {"type":"usage.record","model":"kimi-k2.5","usage":{"inputOther":50,"output":5,"inputCacheRead":5,"inputCacheCreation":0},"usageScope":"turn","time":\(now + 1)}
        """
        try appended.write(to: wireURL, atomically: true, encoding: .utf8)

        let updated = await provider.load()
        XCTAssertEqual(updated.snapshot.todayTokens?.input, 195)
        XCTAssertEqual(updated.snapshot.todayTokens?.cachedInput, 45)
        XCTAssertEqual(updated.snapshot.todayTokens?.output, 25)
    }

    func testMiniMaxReadsDesktopSubscriptionCacheAsSoleSource() async throws {
        let cacheDirectory = try makeTemporaryDirectory()
        let fiveHourEnd = Date().addingTimeInterval(3_600)
        let weeklyEnd = Date().addingTimeInterval(86_400)
        let response = """
        {"model_remains":[
          {
            "model_name":"general",
            "end_time":\(fiveHourEnd.timeIntervalSince1970 * 1_000),
            "weekly_end_time":\(weeklyEnd.timeIntervalSince1970 * 1_000),
            "current_interval_remaining_percent":76.5,
            "current_weekly_remaining_percent":60
          },
          {
            "model_name":"video",
            "current_interval_remaining_percent":10,
            "current_weekly_remaining_percent":20
          }
        ],"base_resp":{"status_code":0,"status_msg":"success"}}
        """
        var cacheData = Data([0x00, 0x01, 0x02, 0x7B])
        cacheData.append(Data("cached-url/ coding_plan/remains".utf8))
        cacheData.append(Data(response.utf8))
        cacheData.append(Data([0x00, 0xFF]))
        try cacheData.write(to: cacheDirectory.appendingPathComponent("cache-entry_0"))

        let result = await MiniMaxUsageProvider(
            cacheDirectory: cacheDirectory
        ).load()

        XCTAssertTrue(result.snapshot.availability.isReady)
        XCTAssertEqual(result.snapshot.windows.count, 2)
        XCTAssertEqual(result.snapshot.windows[0].label, "5 小时")
        XCTAssertEqual(result.snapshot.windows[0].usedPercentage, 23.5)
        XCTAssertEqual(result.snapshot.windows[1].label, "本周")
        XCTAssertEqual(result.snapshot.windows[1].usedPercentage, 40)
        XCTAssertEqual(
            try XCTUnwrap(result.snapshot.windows[0].resetsAt)
                .timeIntervalSince(fiveHourEnd),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(result.snapshot.windows[1].resetsAt)
                .timeIntervalSince(weeklyEnd),
            0,
            accuracy: 0.001
        )
        XCTAssertNil(result.snapshot.todayTokens)
        XCTAssertTrue(result.dailyUsage.isEmpty)
    }

    func testKimiLegacyStatusUpdatesAreDeduplicatedByMessage() async throws {
        let root = try makeTemporaryDirectory()
        let agent = root.appendingPathComponent(
            "sessions/work/session/agents/main",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: agent, withIntermediateDirectories: true)
        let timestamp = Date().timeIntervalSince1970
        let wire = """
        {"timestamp":\(timestamp),"message":{"type":"StatusUpdate","payload":{"message_id":"m1","token_usage":{"input_other":10,"output":2,"input_cache_read":3,"input_cache_creation":1}}}}
        {"timestamp":\(timestamp + 1),"message":{"type":"StatusUpdate","payload":{"message_id":"m1","token_usage":{"input_other":20,"output":4,"input_cache_read":5,"input_cache_creation":1}}}}
        {"timestamp":\(timestamp + 2),"message":{"type":"StatusUpdate","payload":{"message_id":"m2","token_usage":{"input_other":7,"output":3,"input_cache_read":0,"input_cache_creation":0}}}}
        """
        try wire.write(
            to: agent.appendingPathComponent("wire.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = await KimiUsageProvider(
            rootDirectory: root,
            desktopLogURLs: [],
            rateLimitLoader: { nil }
        ).load()

        XCTAssertEqual(result.snapshot.todayTokens?.input, 33)
        XCTAssertEqual(result.snapshot.todayTokens?.cachedInput, 6)
        XCTAssertEqual(result.snapshot.todayTokens?.output, 7)
    }

    func testKimiDesktopSubscriptionUsageIsAddedToCard() async throws {
        let missingCodeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let logs = try makeTemporaryDirectory()
        let logURL = logs.appendingPathComponent("main.log")
        let observedAt = Date()
        let resetAt = observedAt.addingTimeInterval(86_400)
        let logTimestamp = localLogTimestamp(observedAt)
        let resetTimestamp = ISO8601DateFormatter().string(from: resetAt)
        let firstLine = """
        [\(logTimestamp)] [info] [SubscriptionManager] refreshed(sub): level=25 isMember=true omniRatio=0.2176 exhausted=false resetAt=\(resetTimestamp)
        """
        try firstLine.write(to: logURL, atomically: true, encoding: .utf8)

        let provider = KimiUsageProvider(
            rootDirectory: missingCodeRoot,
            desktopLogURLs: [logURL],
            rateLimitLoader: { nil }
        )
        let result = await provider.load()

        XCTAssertTrue(result.snapshot.availability.isReady)
        XCTAssertNil(result.snapshot.todayTokens)
        XCTAssertEqual(result.snapshot.windows.count, 1)
        XCTAssertEqual(result.snapshot.windows.first?.label, "订阅总额度")
        XCTAssertEqual(result.snapshot.windows.first?.resetTimePrecision, .day)
        XCTAssertEqual(result.snapshot.windows.first?.usedPercentage ?? 0, 21.76, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(result.snapshot.windows.first?.resetsAt).timeIntervalSince(resetAt),
            0,
            accuracy: 1
        )

        let secondLine = """

        [\(localLogTimestamp(observedAt.addingTimeInterval(30)))] [info] [SubscriptionManager] refreshed(sub): level=25 isMember=true omniRatio=0.25 exhausted=false resetAt=\(resetTimestamp)
        """
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(secondLine.utf8))
        try handle.close()

        let updated = await provider.load()
        XCTAssertEqual(updated.snapshot.windows.first?.usedPercentage, 25)
    }

    func testKimiOfficialFiveHourAndWeeklyUsageAreAddedToCard() async throws {
        let missingCodeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let observedAt = Date()
        let fiveHourReset = observedAt.addingTimeInterval(3_600)
        let weeklyReset = observedAt.addingTimeInterval(5 * 86_400)

        let result = await KimiUsageProvider(
            rootDirectory: missingCodeRoot,
            desktopLogURLs: [],
            rateLimitLoader: {
                KimiRateLimitSample(
                    fiveHour: KimiRemoteWindow(
                        usedPercentage: 24,
                        resetsAt: fiveHourReset
                    ),
                    weekly: KimiRemoteWindow(
                        usedPercentage: 61,
                        resetsAt: weeklyReset
                    ),
                    observedAt: observedAt
                )
            }
        ).load()

        XCTAssertTrue(result.snapshot.availability.isReady)
        XCTAssertEqual(result.snapshot.windows.map(\.label), ["5 小时", "本周"])
        XCTAssertEqual(result.snapshot.windows.map(\.usedPercentage), [24, 61])
        XCTAssertEqual(result.snapshot.windows.map(\.durationMinutes), [300, 10_080])
        XCTAssertEqual(result.snapshot.windows[0].resetsAt, fiveHourReset)
        XCTAssertEqual(result.snapshot.windows[1].resetsAt, weeklyReset)
    }

    func testKimiUsageAPIDecodesOfficialUsageResponse() throws {
        let observedAt = Date()
        let data = Data(
            """
            {
              "usage": {
                "limit": "100",
                "used": "37",
                "remaining": "63",
                "resetTime": "2026-08-02T03:20:45.248979Z"
              },
              "limits": [
                {
                  "window": {
                    "duration": 300,
                    "timeUnit": "TIME_UNIT_MINUTE"
                  },
                  "detail": {
                    "limit": 100,
                    "remaining": 82,
                    "resetTime": "2026-07-27T05:20:45.248979Z"
                  }
                }
              ]
            }
            """.utf8
        )

        let sample = try XCTUnwrap(KimiUsageAPI.decode(data, observedAt: observedAt))
        XCTAssertEqual(sample.fiveHour?.usedPercentage ?? -1, 18, accuracy: 0.001)
        XCTAssertEqual(sample.weekly?.usedPercentage ?? -1, 37, accuracy: 0.001)
        XCTAssertNotNil(sample.fiveHour?.resetsAt)
        XCTAssertNotNil(sample.weekly?.resetsAt)
        XCTAssertEqual(sample.observedAt, observedAt)
    }

    func testMissingDirectoriesReportCLIUnavailable() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codex = await CodexUsageProvider(rootDirectory: missing).load()
        let claude = await ClaudeUsageProvider(
            claudeDirectory: missing,
            snapshotURL: missing.appendingPathComponent("snapshot"),
            planUsageURL: missing.appendingPathComponent("plan-usage")
        ).load()
        let kimi = await KimiUsageProvider(
            rootDirectory: missing,
            desktopLogURLs: [],
            rateLimitLoader: { nil }
        ).load()
        let miniMax = await MiniMaxUsageProvider(cacheDirectory: missing).load()
        XCTAssertEqual(codex.snapshot.availability, .cliNotInstalled)
        XCTAssertEqual(claude.snapshot.availability, .cliNotInstalled)
        XCTAssertEqual(kimi.snapshot.availability, .cliNotInstalled)
        XCTAssertEqual(miniMax.snapshot.availability, .cliNotInstalled)
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

        let windowStart = Date()
        let currentMilliseconds = windowStart.timeIntervalSince1970 * 1_000
        try """
        {"version":2,"samples":[
          {"t":\(windowStart.addingTimeInterval(-300).timeIntervalSince1970 * 1_000),"org":"test","u":{"fh":0,"sd":0}},
          {"t":\(currentMilliseconds),"org":"test","u":{"fh":6,"sd":7}}
        ]}
        """.write(to: planUsageURL, atomically: true, encoding: .utf8)

        let result = await ClaudeUsageProvider(
            claudeDirectory: claudeRoot,
            snapshotURL: snapshotURL,
            planUsageURL: planUsageURL
        ).load()

        XCTAssertEqual(result.snapshot.windows.map(\.usedPercentage), [6, 7])
        let fiveHourReset = try XCTUnwrap(result.snapshot.windows.first?.resetsAt)
        XCTAssertEqual(fiveHourReset.timeIntervalSince(windowStart), 5 * 60 * 60, accuracy: 0.01)
        let sevenDayReset = try XCTUnwrap(result.snapshot.windows.last?.resetsAt)
        XCTAssertEqual(
            sevenDayReset.timeIntervalSince(windowStart),
            7 * 24 * 60 * 60,
            accuracy: 0.01
        )
        XCTAssertTrue(result.snapshot.availability.isReady)
    }

    func testClaudeDoesNotUseOldContextWindowAsTodaysTokens() async throws {
        let claudeRoot = try makeTemporaryDirectory()
        let support = try makeTemporaryDirectory()
        let snapshotURL = support.appendingPathComponent("claude-snapshot.json")
        let planUsageURL = support.appendingPathComponent("plan-usage-history.json")
        let oldTimestamp = Date().addingTimeInterval(-86_400).timeIntervalSince1970
        try """
        {"collected_at":\(oldTimestamp),"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":\(oldTimestamp + 300)}},"context_window":{"current_usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":50}}}
        """.write(to: snapshotURL, atomically: true, encoding: .utf8)
        try """
        {"version":2,"samples":[{"t":\(Date().timeIntervalSince1970 * 1_000),"org":"test","u":{"fh":6,"sd":7}}]}
        """.write(to: planUsageURL, atomically: true, encoding: .utf8)

        let result = await ClaudeUsageProvider(
            claudeDirectory: claudeRoot,
            snapshotURL: snapshotURL,
            planUsageURL: planUsageURL
        ).load()

        XCTAssertNil(result.snapshot.todayTokens)
        XCTAssertNil(result.snapshot.windows.first?.resetsAt)
    }

    private func codexLine(timestamp: String, input: Int, cached: Int, output: Int, shortPercent: Double, reset: TimeInterval) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":2}},"rate_limits":{"primary":{"used_percent":\(shortPercent),"resets_at":\(reset),"window_minutes":300},"secondary":{"used_percent":20,"resets_at":\(reset + 50000),"window_minutes":10080}}}}
        """
    }

    private func localLogTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AIUsageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
