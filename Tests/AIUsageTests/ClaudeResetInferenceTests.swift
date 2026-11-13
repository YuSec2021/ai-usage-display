import XCTest
@testable import AIUsage

final class ClaudeResetInferenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func snapshot(_ values: [(Double?, Double?)]) async throws -> UsageSnapshot {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let status = root.appendingPathComponent("status.json")
        try Data("{}".utf8).write(to: status)
        let samples: [[String: Any]] = values.enumerated().map { index, value in
            ["t": start(index).timeIntervalSince1970,
             "u": ["fh": value.0.map { $0 as Any } ?? NSNull(), "sd": value.1.map { $0 as Any } ?? NSNull()]]
        }
        let history = root.appendingPathComponent("history.json")
        try JSONSerialization.data(withJSONObject: ["samples": samples]).write(to: history)
        let now = self.now
        return await ClaudeUsageProvider(
            claudeDirectory: root.appendingPathComponent("missing-cli"), snapshotURL: status,
            planUsageURL: history, now: { now }
        ).load().snapshot
    }

    private func start(_ index: Int) -> Date { now.addingTimeInterval(-600 + Double(index) * 60) }

    func testResetSequencesPreserveBothWindowsAndNegativeBoundaryDifference() async throws {
        let cases: [(values: [Double?], short: Int?, weekly: Int?)] = [
            ([], nil, nil), ([0, 0], nil, nil), ([10, 15], nil, nil),
            ([0, 2, 4], 1, 1), ([10, 4, 6], 1, 1), ([0, nil, 2], 2, 2),
            ([0, 2, 0, 3], 3, 3), ([-1, 2], nil, 1), ([0, 2, -1, 3], nil, 3)
        ]
        for value in cases {
            let snapshot = try await snapshot(value.values.map { ($0, $0) })
            XCTAssertEqual(snapshot.windows.first { $0.kind == .short }?.resetsAt,
                           value.short.map { start($0).addingTimeInterval(18_000) })
            XCTAssertEqual(snapshot.windows.first { $0.kind == .long }?.resetsAt,
                           value.weekly.map { start($0).addingTimeInterval(604_800) })
        }
    }

    func testShortAndWeeklyFieldsUseTheirOwnResetStart() async throws {
        let snapshot = try await snapshot([(0, 10), (2, 11), (3, 4)])
        XCTAssertEqual(snapshot.windows.first { $0.kind == .short }?.resetsAt, start(1).addingTimeInterval(18_000))
        XCTAssertEqual(snapshot.windows.first { $0.kind == .long }?.resetsAt, start(2).addingTimeInterval(604_800))
    }
}
