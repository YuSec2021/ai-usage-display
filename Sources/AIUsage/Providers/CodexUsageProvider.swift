import Foundation

actor CodexUsageProvider: UsageProvider {
    nonisolated let id = ProviderID.codex

    private let rootDirectory: URL
    private let calendar: Calendar
    private var fileStates: [URL: FileState] = [:]
    private let initialTailBytes = 1_048_576

    init(rootDirectory: URL = ProviderPaths.codexDirectory, calendar: Calendar = .current) {
        self.rootDirectory = rootDirectory
        self.calendar = calendar
    }

    func load() async -> ProviderResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return ProviderResult(snapshot: .empty(id, availability: .cliNotInstalled), dailyUsage: [])
        }

        let files = jsonlFiles(fileManager: fileManager)
        guard !files.isEmpty else {
            return ProviderResult(snapshot: .empty(id, availability: .waitingForFirstSample), dailyUsage: [])
        }

        let cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date())) ?? .distantPast
        let fileSet = Set(files)
        fileStates = fileStates.filter { fileSet.contains($0.key) }

        let newestFile = files.max {
            (fileMetadata($0)?.modifiedAt ?? .distantPast) < (fileMetadata($1)?.modifiedAt ?? .distantPast)
        }

        for file in files {
            guard let metadata = fileMetadata(file) else { continue }
            let existing = fileStates[file]
            if existing == nil, file != newestFile, metadata.modifiedAt < cutoff { continue }
            guard existing?.size != metadata.size || existing?.modifiedAt != metadata.modifiedAt else { continue }
            fileStates[file] = parseChanges(in: file, metadata: metadata, previousState: existing)
        }

        var latest: LatestEvent?
        var buckets: [Date: TokenUsage] = [:]
        for state in fileStates.values {
            if let candidate = state.latest, latest == nil || candidate.date >= latest!.date {
                latest = candidate
            }
            for (day, usage) in state.dailyUsage where day >= cutoff {
                buckets[day, default: .zero] = buckets[day, default: .zero] + usage
            }
        }

        guard let latest else {
            return ProviderResult(snapshot: .empty(id, availability: .unsupportedFormat), dailyUsage: [])
        }

        let snapshot = UsageSnapshot(
            provider: id,
            windows: Self.makeWindows(latest.event.rateLimits),
            todayTokens: buckets[calendar.startOfDay(for: Date())],
            estimatedCostUSD: nil,
            observedAt: latest.date,
            availability: .ready(lastUpdated: latest.date)
        )
        let daily = buckets.map { DailyUsage(date: $0.key, provider: id, tokens: $0.value) }.sorted { $0.date < $1.date }
        return ProviderResult(snapshot: snapshot, dailyUsage: daily)
    }

    private func parseChanges(in url: URL, metadata: FileMetadata, previousState: FileState?) -> FileState {
        var state = previousState ?? FileState()
        let wasRewritten = metadata.size < state.offset || (metadata.size == state.size && metadata.modifiedAt != state.modifiedAt)
        if wasRewritten { state = FileState() }

        let initialRead = state.offset == 0
        let tailBytes = UInt64(initialTailBytes)
        let startOffset = initialRead
            ? (metadata.size > tailBytes ? metadata.size - tailBytes : 0)
            : state.offset
        guard metadata.size >= startOffset,
              let handle = try? FileHandle(forReadingFrom: url) else {
            state.size = metadata.size
            state.modifiedAt = metadata.modifiedAt
            return state
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: startOffset)
            var incoming = try handle.readToEnd() ?? Data()
            if initialRead, startOffset > 0, let newline = incoming.firstIndex(of: 0x0A) {
                incoming.removeSubrange(incoming.startIndex...newline)
            }

            var combined = state.remainder
            combined.append(incoming)
            var lines = combined.split(separator: 0x0A, omittingEmptySubsequences: false)
            var finalLine: Data?
            if combined.last != 0x0A, let final = lines.popLast() {
                finalLine = Data(final)
            }
            state.remainder = Data()

            for rawLine in lines where !rawLine.isEmpty {
                _ = consume(Data(rawLine), metadata: metadata, state: &state)
            }
            if let finalLine, !finalLine.isEmpty,
               !consume(finalLine, metadata: metadata, state: &state) {
                // Claude/Codex can be writing while the refresh runs. Retry only an
                // incomplete final JSON object, without rereading the whole file.
                state.remainder = finalLine
            }
            state.offset = metadata.size
        } catch {
            // Keep the last valid state and retry this file on the next refresh.
        }

        state.size = metadata.size
        state.modifiedAt = metadata.modifiedAt
        return state
    }

    @discardableResult
    private func consume(_ line: Data, metadata: FileMetadata, state: inout FileState) -> Bool {
        guard let envelope = try? JSONDecoder().decode(CodexEnvelope.self, from: line) else {
            return false
        }
        // A valid unrelated event is complete and must not be retained as a partial line.
        guard envelope.type == "event_msg",
              envelope.payload?.type == "token_count",
              let event = envelope.payload else { return true }
        let timestamp = Self.parseDate(envelope.timestamp) ?? metadata.modifiedAt

        if let total = event.info?.totalTokenUsage {
            let current = total.asUsage
            let delta: TokenUsage
            if let previous = state.previousTotal {
                delta = TokenUsage(
                    input: max(current.input - previous.input, 0),
                    cachedInput: max(current.cachedInput - previous.cachedInput, 0),
                    output: max(current.output - previous.output, 0),
                    reasoningOutput: max(current.reasoningOutput - previous.reasoningOutput, 0)
                )
            } else {
                delta = current
            }
            state.previousTotal = current
            let day = calendar.startOfDay(for: timestamp)
            state.dailyUsage[day, default: .zero] = state.dailyUsage[day, default: .zero] + delta
        }

        if state.latest == nil || timestamp >= state.latest!.date {
            state.latest = LatestEvent(date: timestamp, event: event)
        }
        return true
    }

    private func jsonlFiles(fileManager: FileManager) -> [URL] {
        ["sessions", "archived_sessions"].flatMap { name -> [URL] in
            let directory = rootDirectory.appendingPathComponent(name, isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return enumerator.compactMap { item in
                guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
                return url
            }
        }
    }

    private func fileMetadata(_ url: URL) -> FileMetadata? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modifiedAt = values.contentModificationDate else { return nil }
        return FileMetadata(size: UInt64(size), modifiedAt: modifiedAt)
    }

    private static func makeWindows(_ limits: CodexRateLimits?) -> [RateLimitWindow] {
        guard let limits else { return [] }
        var result: [RateLimitWindow] = []
        if let primary = limits.primary {
            result.append(window(primary, kind: .short, fallbackLabel: L10n.text("短周期", "Short window")))
        }
        if let secondary = limits.secondary {
            result.append(window(secondary, kind: .long, fallbackLabel: L10n.text("长周期", "Long window")))
        }
        return result
    }

    private static func window(_ value: CodexRateWindow, kind: WindowKind, fallbackLabel: String) -> RateLimitWindow {
        let minutes = value.windowMinutes
        let label: String
        if let minutes, minutes % 10_080 == 0 {
            let days = minutes / 10_080 * 7
            label = L10n.text("\(days) 天", "\(days) days")
        } else if let minutes, minutes % 60 == 0 {
            let hours = minutes / 60
            label = L10n.text("\(hours) 小时", "\(hours) hours")
        } else {
            label = fallbackLabel
        }
        return RateLimitWindow(
            kind: kind,
            label: label,
            usedPercentage: value.usedPercent ?? 0,
            resetsAt: value.resetsAt.map { Date(timeIntervalSince1970: $0) },
            durationMinutes: minutes
        )
    }

    nonisolated static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct FileMetadata {
    let size: UInt64
    let modifiedAt: Date
}

private struct FileState {
    var size: UInt64 = 0
    var modifiedAt: Date = .distantPast
    var offset: UInt64 = 0
    var remainder = Data()
    var previousTotal: TokenUsage?
    var dailyUsage: [Date: TokenUsage] = [:]
    var latest: LatestEvent?
}

private struct LatestEvent {
    let date: Date
    let event: CodexTokenEvent
}

struct CodexEnvelope: Decodable {
    let timestamp: String?
    let type: String
    let payload: CodexTokenEvent?
}

struct CodexTokenEvent: Decodable {
    let type: String?
    let info: CodexTokenInfo?
    let rateLimits: CodexRateLimits?

    enum CodingKeys: String, CodingKey {
        case type, info
        case rateLimits = "rate_limits"
    }
}

struct CodexTokenInfo: Decodable {
    let lastTokenUsage: CodexTokenValues?
    let totalTokenUsage: CodexTokenValues?
    let modelContextWindow: Int?

    enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
        case modelContextWindow = "model_context_window"
    }
}

struct CodexTokenValues: Decodable {
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
    let reasoningOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
    }

    var asUsage: TokenUsage {
        TokenUsage(
            input: inputTokens ?? 0,
            cachedInput: cachedInputTokens ?? 0,
            output: outputTokens ?? 0,
            reasoningOutput: reasoningOutputTokens ?? 0
        )
    }
}

struct CodexRateLimits: Decodable {
    let primary: CodexRateWindow?
    let secondary: CodexRateWindow?
}

struct CodexRateWindow: Decodable {
    let usedPercent: Double?
    let resetsAt: Double?
    let windowMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
        case windowMinutes = "window_minutes"
    }
}
