import XCTest
import Compression
import zlib
@testable import AIUsage

final class MiniMaxCacheTests: XCTestCase {
    // Generated from synthetic quota JSON with the independent Brotli CLI.
    private let goldenBrotli = Data(base64Encoded: "HwEBAMS0OeUvmSOusoM+zSGb7VzH8tvd7jboAgqCUZJ0o6gyTbeJ4CleOk0WdVZ60Y+m7ZjjvoLK6DzIvgXh14mlg412MFxTQAdPvNrYjwdjSIIJnd8vb4fseGLj6+QPhDC2gBzWTW77KkeQx2q7HpevgLFF9Nc2qMq8tOsEepFVpiBA/v8D")!

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func response(used: String = "24%", weeklyStatus: Int = 3, status: Int = 0) -> Data {
        Data("""
        {"model_remains":[{"model_name":"general","end_time":2000000000000,"weekly_end_time":2000500000000,"current_interval_used_percent":"\(used)","current_interval_status":1,"current_weekly_used_percent":"0%","current_weekly_status":\(weeklyStatus)}],"base_resp":{"status_code":\(status)}}
        """.utf8)
    }

    private func compress(_ body: Data) throws -> Data {
        var result = [UInt8](repeating: 0, count: max(body.count * 2, 1_024))
        let capacity = result.count
        let count = body.withUnsafeBytes { bytes in
            compression_encode_buffer(&result, capacity, bytes.bindMemory(to: UInt8.self).baseAddress!, bytes.count, nil, COMPRESSION_BROTLI)
        }
        XCTAssertGreaterThan(count, 0)
        return Data(result.prefix(count))
    }

    private func entry(_ body: Data, encoding: String? = "br", key: String = "https://www.minimaxi.com/backend/account/token_plan/remains_percent") -> Data {
        func record(_ magic: UInt64, _ first: UInt32, _ second: UInt32, _ third: UInt32) -> Data {
            var data = Data()
            func append<T: FixedWidthInteger>(_ value: T) {
                var value = value.littleEndian
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            }
            append(magic); append(first); append(second); append(third); append(UInt32(0))
            return data
        }
        func checksum(_ data: Data) -> UInt32 {
            data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))) }
        }
        let keyBytes = Data(key.utf8)
        let headers = Data(("HTTP/1.1 200 OK\0content-type: application/json\0" + (encoding.map { "content-encoding: \($0)\0" } ?? "")).utf8)
        var result = record(0xfcfb6d1ba7725c30, 5, UInt32(keyBytes.count), 0)
        result.append(keyBytes)
        result.append(body)
        result.append(record(0xf4fa6f45970d41d8, 1, checksum(body), 0))
        result.append(headers)
        result.append(Data(repeating: 0, count: 32)) // optional key SHA-256
        result.append(record(0xf4fa6f45970d41d8, 3, checksum(headers), UInt32(headers.count)))
        return result
    }

    func testBrotliCacheMatchesTwentyFourPercentAndUnlimitedWeek() async throws {
        let root = try directory()
        try entry(try compress(response())).write(to: root.appendingPathComponent("quota_0"))
        let result = await MiniMaxUsageProvider(cacheDirectory: root).load()
        XCTAssertTrue(result.snapshot.availability.isReady)
        XCTAssertEqual(result.snapshot.fiveHourWindow()?.usedPercentage, 24)
        let weekly = try XCTUnwrap(result.snapshot.windows.first { $0.kind == .long })
        XCTAssertTrue(weekly.isUnlimited)
        XCTAssertNil(weekly.resetsAt)
        XCTAssertEqual(weekly.durationMinutes, 10_080)
        XCTAssertNil(result.snapshot.todayTokens)
        XCTAssertTrue(result.dailyUsage.isEmpty)
    }

    func testIndependentBrotliFixtureDecodes() throws {
        let data = entry(goldenBrotli)
        let quota = try XCTUnwrap(MiniMaxUsageProvider.quotaResponse(from: data)?.preferredTextQuota)
        XCTAssertEqual(quota.intervalUsedPercentage, 24)
        XCTAssertTrue(quota.isWeeklyUnlimited)
    }

    func testStandardBodyUsesJSONDecodingWithoutLegacyScanning() throws {
        let escapedKey = response().replacing(Data("model_remains".utf8), with: Data(#"model\u005fremains"#.utf8))
        let quota = MiniMaxUsageProvider.quotaResponse(from: entry(try compress(escapedKey)))?.preferredTextQuota
        XCTAssertEqual(quota?.intervalUsedPercentage, 24)
        var embedded = Data("non-json prefix ".utf8)
        embedded.append(response())
        embedded.append(Data(" trailing bytes".utf8))
        XCTAssertNil(MiniMaxUsageProvider.quotaResponse(from: entry(try compress(embedded))))
        XCTAssertEqual(MiniMaxUsageProvider.quotaResponse(from: embedded)?.preferredTextQuota?.intervalUsedPercentage, 24)
        let legacyObject: [String: Any] = [
            "base_resp": ["status_code": 0, "status_msg": "braces } { and escaped quote \" with slash \\"],
            "model_remains": [["model_name": "general", "current_interval_remaining_percent": 76]]
        ]
        var legacy = Data([0x00, 0x7B, 0xFF])
        legacy.append(try JSONSerialization.data(withJSONObject: legacyObject, options: .sortedKeys))
        legacy.append(Data([0xFF, 0x00]))
        XCTAssertEqual(MiniMaxUsageProvider.quotaResponse(from: legacy)?.preferredTextQuota?.intervalUsedPercentage, 24)
    }

    func testRefreshReadsChangedFileAndRetainsSampleDuringPartialWrite() async throws {
        let root = try directory()
        let file = root.appendingPathComponent("quota_0")
        try entry(try compress(response())).write(to: file)
        let provider = MiniMaxUsageProvider(cacheDirectory: root)
        let initial = await provider.load()
        try entry(try compress(response(used: "37%"))).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: file.path)
        let updated = await provider.load()
        XCTAssertEqual(updated.snapshot.fiveHourWindow()?.usedPercentage, 37)
        XCTAssertNotEqual(updated.snapshot, initial.snapshot)
        let complete = try Data(contentsOf: file)
        try complete.prefix(complete.count / 2).write(to: file)
        let incomplete = await provider.load()
        XCTAssertEqual(incomplete.snapshot.fiveHourWindow()?.usedPercentage, 37)
        XCTAssertEqual(incomplete.snapshot.observedAt, updated.snapshot.observedAt)
        XCTAssertTrue(incomplete.snapshot.availability.isStale)
        try entry(try compress(response(used: "0%"))).write(to: file)
        let reset = await provider.load()
        XCTAssertEqual(reset.snapshot.fiveHourWindow()?.usedPercentage, 0)
        XCTAssertTrue(reset.snapshot.availability.isReady)
    }

    func testLegacyPlaintextAndNumericPercentagesRemainSupported() throws {
        let legacy = Data(#"{"model_remains":[{"model_name":"general","current_interval_remaining_percent":76,"current_weekly_remaining_percent":60}]}"#.utf8)
        let quota = try XCTUnwrap(MiniMaxUsageProvider.quotaResponse(from: entry(legacy, encoding: nil))?.preferredTextQuota)
        XCTAssertEqual(quota.intervalUsedPercentage, 24)
        XCTAssertEqual(quota.weeklyUsedPercentage, 40)
        XCTAssertFalse(quota.isWeeklyUnlimited)
        let numeric = response().replacing(Data(#""24%""#.utf8), with: Data("24".utf8))
        XCTAssertEqual(MiniMaxUsageProvider.quotaResponse(from: numeric)?.preferredTextQuota?.intervalUsedPercentage, 24)
        let invalid = response(used: "2%4")
        XCTAssertNil(MiniMaxUsageProvider.quotaResponse(from: invalid)?.preferredTextQuota?.intervalUsedPercentage)
    }

    func testMalformedUnrelatedAndOversizedCompressedResponsesAreRejected() throws {
        let valid = entry(try compress(response()))
        XCTAssertNil(MiniMaxUsageProvider.quotaResponse(from: Data(valid.dropLast())))
        XCTAssertNil(MiniMaxUsageProvider.quotaResponse(from: entry(Data([0xDE, 0xAD]))))
        XCTAssertNil(MiniMaxUsageProvider.quotaResponse(from: entry(try compress(response()), key: "https://example.test/unrelated")))
        XCTAssertNil(MiniMaxUsageProvider.quotaResponse(from: entry(try compress(response(status: 1001)))))
        var badCRC = valid
        badCRC[24 + "https://www.minimaxi.com/backend/account/token_plan/remains_percent".utf8.count] ^= 1
        XCTAssertNil(MiniMaxUsageProvider.quotaResponse(from: badCRC))
        let large = try compress(Data(repeating: 65, count: 2_097_152))
        XCTAssertNil(MiniMaxUsageProvider.quotaResponse(from: entry(large)))
    }

    func testNewInvalidEntryDoesNotMaskOlderValidQuota() async throws {
        let root = try directory()
        let good = root.appendingPathComponent("good_0")
        try entry(try compress(response())).write(to: good)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30)], ofItemAtPath: good.path)
        try entry(try compress(response(status: 1001))).write(to: root.appendingPathComponent("failed_0"))
        let result = await MiniMaxUsageProvider(cacheDirectory: root).load()
        XCTAssertEqual(result.snapshot.fiveHourWindow()?.usedPercentage, 24)
    }
}

private extension Data {
    func replacing(_ original: Data, with replacement: Data) -> Data {
        guard let range = range(of: original) else { return self }
        var copy = self
        copy.replaceSubrange(range, with: replacement)
        return copy
    }
}
