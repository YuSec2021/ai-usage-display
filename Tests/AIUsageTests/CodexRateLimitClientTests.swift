import XCTest
@testable import AIUsage

final class CodexRateLimitClientTests: XCTestCase {
    private func executable(_ script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("codex")
        try ("#!/bin/sh\n" + script).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func server(response: String) throws -> URL {
        try executable("""
        [ "$1" = 'app-server' ] || exit 1
        IFS= read -r request || exit 1
        case "$request" in *'"initialize"'*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"id":0,"result":{"userAgent":"fixture"}}'
        IFS= read -r notification || exit 1
        case "$notification" in *'"initialized"'*) ;; *) exit 1 ;; esac
        IFS= read -r request || exit 1
        case "$request" in *'"account/rateLimits/read"'*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"method":"unrelated/notification","params":{}}'
        printf '%s\\n' '\(response)'
        """)
    }

    func testHandshakeSelectsCodexBucketAndPreservesZeroUsage() async throws {
        let url = try server(response: #"{"id":1,"result":{"rateLimits":{"limitId":"other","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":99}},"codex":{"primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":29,"windowDurationMins":10080,"resetsAt":2000500000}}}}}"#)
        let limits = await CodexRateLimitClient(executableURL: url).read()
        XCTAssertEqual(limits?.primary?.usedPercent, 0)
        XCTAssertEqual(limits?.primary?.windowMinutes, 300)
        XCTAssertEqual(limits?.primary?.resetsAt, 2_000_000_000)
        XCTAssertEqual(limits?.secondary?.usedPercent, 29)
    }

    func testLegacyResponseWithoutBucketMapIsSupported() async throws {
        let url = try server(response: #"{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":17,"windowDurationMins":300}}}}"#)
        let limits = await CodexRateLimitClient(executableURL: url).read()
        XCTAssertEqual(limits?.primary?.usedPercent, 17)
        XCTAssertNil(limits?.primary?.resetsAt)
    }

    func testOtherBucketsAndRPCFailuresDoNotBecomeCodexQuota() async throws {
        for response in [
            #"{"id":1,"result":{"rateLimits":{"limitId":"other","primary":{"usedPercent":99}}}}"#,
            #"{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":99}}}}}"#,
            #"{"id":1,"error":{"code":-32000,"message":"not signed in"}}"#,
            #"{"id":1,"result":{"rateLimits":{"primary":{"windowDurationMins":300}}}}"#
        ] {
            let url = try server(response: response)
            let limits = await CodexRateLimitClient(executableURL: url).read()
            XCTAssertNil(limits)
        }
    }

    func testMissingExitedAndUnresponsiveCLIHaveBoundedFailure() async throws {
        let missing = await CodexRateLimitClient(executableURL: URL(fileURLWithPath: "/nonexistent/codex")).read()
        XCTAssertNil(missing)
        let exited = try executable("exit 1")
        let earlyExit = await CodexRateLimitClient(executableURL: exited).read()
        XCTAssertNil(earlyExit)
        let hung = try executable("exec /bin/sleep 10")
        let start = ProcessInfo.processInfo.systemUptime
        let timedOut = await CodexRateLimitClient(executableURL: hung, timeout: 0.1).read()
        XCTAssertNil(timedOut)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    }
}
