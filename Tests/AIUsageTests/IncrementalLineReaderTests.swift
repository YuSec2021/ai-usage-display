import XCTest
@testable import AIUsage

final class IncrementalLineReaderTests: XCTestCase {
    private func file() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("events.jsonl")
    }

    private func size(_ file: URL) throws -> UInt64 { UInt64(try Data(contentsOf: file).count) }

    func testPartialLineCompletesOnceAndValidUnrelatedEventIsNotRetained() throws {
        let file = try file()
        try Data("{\"value\":1}\n{\"value\":".utf8).write(to: file)
        var values: [Int] = []
        func consume(_ data: Data) -> Bool {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            if let value = object["value"] as? Int { values.append(value) }
            return true
        }
        var cursor = try IncrementalLineReader.read(from: file, size: size(file), cursor: .init(), consume: consume)
        XCTAssertEqual(values, [1])
        XCTAssertFalse(cursor.remainder.isEmpty)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("2}\n{\"unrelated\":true}".utf8))
        try handle.close()
        cursor = try IncrementalLineReader.read(from: file, size: size(file), cursor: cursor, consume: consume)
        XCTAssertEqual(values, [1, 2])
        XCTAssertTrue(cursor.remainder.isEmpty)
        _ = try IncrementalLineReader.read(from: file, size: size(file), cursor: cursor, consume: consume)
        XCTAssertEqual(values, [1, 2])
    }

    func testFileSizeSnapshotLeavesLaterAppendsForNextRead() throws {
        let file = try file()
        let first = Data("one\n".utf8), both = Data("one\ntwo\n".utf8)
        try both.write(to: file)
        var lines: [String] = []
        let consume: (Data) -> Bool = { lines.append(String(decoding: $0, as: UTF8.self)); return true }
        let cursor = try IncrementalLineReader.read(from: file, size: UInt64(first.count), cursor: .init(), consume: consume)
        XCTAssertEqual(lines, ["one"])
        _ = try IncrementalLineReader.read(from: file, size: UInt64(both.count), cursor: cursor, consume: consume)
        XCTAssertEqual(lines, ["one", "two"])
    }

    func testTailReadDropsInitialFragmentAndAcceptsFinalLineWithoutNewline() throws {
        let file = try file()
        try Data("fragment\ncomplete\nfinal".utf8).write(to: file)
        var lines: [String] = []
        let cursor = try IncrementalLineReader.read(from: file, size: size(file), cursor: .init(), initialOffset: { _ in 3 }) {
            lines.append(String(decoding: $0, as: UTF8.self)); return true
        }
        XCTAssertEqual(lines, ["complete", "final"])
        XCTAssertTrue(cursor.remainder.isEmpty)
    }

    func testFailedAndShortReadsDoNotConsumeOrAdvanceCursor() throws {
        let file = try file()
        var calls = 0
        let consume: (Data) -> Bool = { _ in calls += 1; return true }
        XCTAssertThrowsError(try IncrementalLineReader.read(from: file, size: 10, cursor: .init(), consume: consume))
        try Data("row\n".utf8).write(to: file)
        XCTAssertThrowsError(try IncrementalLineReader.read(from: file, size: 10, cursor: .init(), consume: consume))
        XCTAssertEqual(calls, 0)
        let cursor = try IncrementalLineReader.read(from: file, size: size(file), cursor: .init(), consume: consume)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(cursor.offset, 4)
    }

    func testProvidersResetBusinessStateOnSameSizeRewriteAndTruncation() async throws {
        let now = Date()
        let timestamp = ISO8601DateFormatter().string(from: now)
        for id in [ProviderID.codex, .claudeCode, .kimiCode] {
            let root = try file().deletingLastPathComponent()
            let file: URL
            let provider: any UsageProvider
            let line: (Int) -> String
            switch id {
            case .codex:
                file = root.appendingPathComponent("sessions/events.jsonl")
                provider = CodexUsageProvider(rootDirectory: root)
                line = { #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#($0)}}}}"# }
            case .claudeCode:
                file = root.appendingPathComponent("projects/sample/events.jsonl")
                let snapshot = root.appendingPathComponent("snapshot.json")
                try Data("{}".utf8).write(to: snapshot)
                provider = ClaudeUsageProvider(claudeDirectory: root, snapshotURL: snapshot,
                    planUsageURL: root.appendingPathComponent("missing.json"), now: { now })
                line = { #"{"timestamp":"\#(timestamp)","message":{"id":"fixture","usage":{"input_tokens":\#($0),"output_tokens":0}}}"# }
            case .kimiCode:
                file = root.appendingPathComponent("sessions/sample/wire.jsonl")
                provider = KimiUsageProvider(rootDirectory: root, desktopLogURLs: [], rateLimitLoader: { nil })
                line = { #"{"type":"usage.record","model":"fixture","usage":{"inputOther":\#($0)},"usageScope":"turn","time":\#(now.timeIntervalSince1970 * 1_000)}"# }
            case .miniMax: continue
            }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            for (step, amount) in [9, 2, 0, 3].enumerated() {
                let data = amount == 0 ? Data() : Data(line(amount).utf8)
                try data.write(to: file)
                try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(Double(step))], ofItemAtPath: file.path)
                let result = await provider.load()
                XCTAssertEqual(result.dailyUsage.reduce(0) { $0 + $1.tokens.total }, amount, "\(id), step \(step)")
                let unchanged = await provider.load()
                XCTAssertEqual(unchanged.dailyUsage, result.dailyUsage)
            }
        }
    }
}
