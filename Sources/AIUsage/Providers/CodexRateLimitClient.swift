import Foundation
import Darwin

/// Uses the installed CLI's own authentication. No credentials or conversations
/// cross this stdio connection, and no thread/turn is created.
struct CodexRateLimitClient: Sendable {
    var executableURL: URL? = nil
    var timeout: TimeInterval = 8

    func read() async -> CodexRateLimits? {
        guard let executable = executableURL ?? Self.findExecutable() else { return nil }
        let timeout = self.timeout
        return await Task.detached(priority: .utility) {
            Self.read(executable: executable, timeout: timeout)
        }.value
    }

    private static func findExecutable() -> URL? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { String($0) + "/codex" }
        // GUI apps do not inherit the user's interactive shell PATH.
        let candidates = paths + [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        ]
        return candidates.first { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private static func read(executable: URL, timeout: TimeInterval) -> CodexRateLimits? {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // A CLI that exits during initialization must not deliver SIGPIPE to the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let outputDescriptor = output.fileHandleForReading.fileDescriptor
        _ = fcntl(outputDescriptor, F_SETFL, fcntl(outputDescriptor, F_GETFL) | O_NONBLOCK)
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            // Never leave a hung child behind, or wait indefinitely on shutdown.
            let deadline = ProcessInfo.processInfo.systemUptime + 0.2
            while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try? output.fileHandleForReading.close()
        }

        func send(_ value: [String: Any]) -> Bool {
            guard var data = try? JSONSerialization.data(withJSONObject: value, options: .withoutEscapingSlashes) else { return false }
            data.append(0x0A)
            do { try input.fileHandleForWriting.write(contentsOf: data); return true }
            catch { return false }
        }
        guard send([
            "id": 0, "method": "initialize",
            "params": ["clientInfo": ["name": "ai_usage", "version": "1.0"]]
        ]) else { return nil }

        let deadline = ProcessInfo.processInfo.systemUptime + max(timeout, 0)
        var buffer = Data()
        var initialized = false
        var bytesRead = 0
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: outputDescriptor, events: Int16(POLLIN), revents: 0)
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            let waitMilliseconds = Int32(min(max(remaining * 1_000, 0), 100))
            let status = poll(&descriptor, 1, waitMilliseconds)
            if status < 0 { if errno == EINTR { continue }; return nil }
            if status == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.read(outputDescriptor, &bytes, bytes.count)
            if count < 0, errno == EAGAIN || errno == EINTR { continue }
            guard count > 0 else { return nil }
            let data = Data(bytes.prefix(count))
            bytesRead += data.count
            guard bytesRead <= 1_048_576 else { return nil }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let message = try? JSONDecoder().decode(Response.self, from: line), let id = message.id else { continue }
                if id == 0, !initialized {
                    guard !message.hasError, message.hasResult,
                          send(["method": "initialized", "params": [:]]),
                          send(["id": 1, "method": "account/rateLimits/read"]) else { return nil }
                    initialized = true
                } else if id == 1, initialized {
                    guard !message.hasError else { return nil }
                    return message.result?.codexLimits
                }
            }
        }
        return nil
    }

    private struct Response: Decodable {
        let id: Int?
        let hasError: Bool
        let hasResult: Bool
        let result: LimitsResponse?

        enum CodingKeys: String, CodingKey { case id, result, error }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try? values.decode(Int.self, forKey: .id)
            hasError = values.contains(.error)
            hasResult = values.contains(.result)
            result = try? values.decode(LimitsResponse.self, forKey: .result)
        }
    }

    private struct LimitsResponse: Decodable {
        let rateLimits: Limits?
        let rateLimitsByLimitId: [String: Limits]?

        var codexLimits: CodexRateLimits? {
            // Other model buckets must never become the Codex account ring.
            let limits: Limits?
            if let buckets = rateLimitsByLimitId, !buckets.isEmpty {
                limits = buckets["codex"]
            } else {
                limits = rateLimits.flatMap { $0.limitId == nil || $0.limitId == "codex" ? $0 : nil }
            }
            return limits.map { CodexRateLimits(primary: $0.primary?.value, secondary: $0.secondary?.value) }
        }
    }

    private struct Limits: Decodable {
        let limitId: String?
        let primary: Window?
        let secondary: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Double?

        var value: CodexRateWindow {
            CodexRateWindow(usedPercent: usedPercent, resetsAt: resetsAt, windowMinutes: windowDurationMins)
        }
    }
}
