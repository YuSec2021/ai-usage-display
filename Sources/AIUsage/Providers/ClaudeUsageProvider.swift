import Foundation

actor ClaudeUsageProvider: UsageProvider {
    nonisolated let id = ProviderID.claudeCode
    let claudeDirectory: URL
    let snapshotURL: URL
    let planUsageURL: URL
    let calendar: Calendar
    private var metricCache: ClaudeMetricCache?
    private var transcriptStates: [URL: ClaudeTranscriptFileState] = [:]
    private let transcriptScanChunkBytes: Int
    private let now: @Sendable () -> Date

    init(
        claudeDirectory: URL = ProviderPaths.claudeDirectory,
        snapshotURL: URL = ProviderPaths.applicationSupport.appendingPathComponent("claude-snapshot.json"),
        planUsageURL: URL = ProviderPaths.claudeDesktopUsageHistory,
        calendar: Calendar = .current,
        transcriptScanChunkBytes: Int = 4 * 1_024 * 1_024,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.claudeDirectory = claudeDirectory
        self.snapshotURL = snapshotURL
        self.planUsageURL = planUsageURL
        self.calendar = calendar
        self.transcriptScanChunkBytes = max(transcriptScanChunkBytes, 1)
        self.now = now
    }

    func load() async -> ProviderResult {
        let hasCLIData = FileManager.default.fileExists(atPath: claudeDirectory.path)
        let hasDesktopData = FileManager.default.fileExists(atPath: planUsageURL.path)
        guard hasCLIData || hasDesktopData else {
            return ProviderResult(snapshot: .empty(id, availability: .cliNotInstalled), dailyUsage: [])
        }

        let daily = hasCLIData ? loadDailyUsage() : []
        let statusValue = (try? Data(contentsOf: snapshotURL))
            .flatMap { try? JSONDecoder().decode(ClaudeStatusSnapshot.self, from: $0) }
        let desktopSample = loadLatestDesktopUsage()

        guard statusValue != nil || desktopSample != nil else {
            let state: ProviderAvailability = ClaudeIntegrationManager.isInstalled
                ? .waitingForFirstSample
                : .integrationNotInstalled
            return ProviderResult(snapshot: .empty(id, availability: state), dailyUsage: daily)
        }

        let statusObservedAt = statusValue?.collectedAt.map(Date.init(timeIntervalSince1970:))
            ?? (try? snapshotURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        let useDesktopSample = desktopSample.map { $0.observedAt > statusObservedAt } ?? false
        let observedAt = useDesktopSample ? desktopSample!.observedAt : statusObservedAt
        var windows: [RateLimitWindow] = []
        let fiveHour = useDesktopSample
            ? desktopSample?.fiveHour.map {
                ClaudeRateWindow(
                    usedPercentage: $0,
                    resetsAt: desktopSample?.fiveHourResetsAt?.timeIntervalSince1970
                        ?? futureResetTimestamp(statusValue?.rateLimits?.fiveHour?.resetsAt)
                )
            }
            : statusValue?.rateLimits?.fiveHour
        let sevenDay = useDesktopSample
            ? desktopSample?.sevenDay.map {
                ClaudeRateWindow(
                    usedPercentage: $0,
                    resetsAt: futureResetTimestamp(statusValue?.rateLimits?.sevenDay?.resetsAt)
                        ?? desktopSample?.sevenDayResetsAt?.timeIntervalSince1970
                )
            }
            : statusValue?.rateLimits?.sevenDay
        if let fiveHour {
            windows.append(RateLimitWindow(
                kind: .short,
                label: L10n.text("5 小时", "5 hours"),
                usedPercentage: fiveHour.usedPercentage ?? 0,
                resetsAt: fiveHour.resetsAt.map(Date.init(timeIntervalSince1970:)),
                durationMinutes: 300
            ))
        }
        if let sevenDay {
            windows.append(RateLimitWindow(
                kind: .long,
                label: L10n.text("7 天", "7 days"),
                usedPercentage: sevenDay.usedPercentage ?? 0,
                resetsAt: sevenDay.resetsAt.map(Date.init(timeIntervalSince1970:)),
                durationMinutes: 10_080
            ))
        }

        let today = daily.first { calendar.isDateInToday($0.date) }?.tokens
        let snapshot = UsageSnapshot(
            provider: id,
            windows: windows,
            // The status-line value describes one context window, not a daily
            // total. Never present an old session snapshot as today's usage.
            todayTokens: today,
            estimatedCostUSD: statusValue?.cost?.totalCostUSD.map { Decimal($0) },
            observedAt: observedAt,
            // Claude only updates usage while it is being called. The last
            // valid sample remains current until the next Claude interaction.
            availability: .ready(lastUpdated: observedAt)
        )
        return ProviderResult(snapshot: snapshot, dailyUsage: daily)
    }

    private func loadLatestDesktopUsage() -> ClaudeDesktopUsageSample? {
        guard let data = try? Data(contentsOf: planUsageURL, options: [.mappedIfSafe]),
              let history = try? JSONDecoder().decode(ClaudeDesktopUsageHistory.self, from: data) else {
            return nil
        }
        let samples = history.samples
            .compactMap(\.normalized)
            .sorted { $0.observedAt < $1.observedAt }
        guard var latest = samples.last else { return nil }
        latest.fiveHourResetsAt = inferredFiveHourReset(from: samples)
        latest.sevenDayResetsAt = inferredSevenDayReset(from: samples)
        return latest
    }

    private func inferredFiveHourReset(from samples: [ClaudeDesktopUsageSample]) -> Date? {
        var windowStartedAt: Date?
        var previousUsage: Double?

        for sample in samples {
            guard let usage = sample.fiveHour else { continue }
            defer { previousUsage = usage }

            if usage <= 0 {
                windowStartedAt = nil
                continue
            }

            if let previousUsage, previousUsage == 0 || usage < previousUsage {
                windowStartedAt = sample.observedAt
            }
        }

        guard let windowStartedAt else { return nil }
        let reset = windowStartedAt.addingTimeInterval(5 * 60 * 60)
        return reset > Date() ? reset : nil
    }

    /// Claude Desktop stores weekly usage samples but not the corresponding
    /// reset timestamp. A weekly window begins when usage changes from zero to
    /// a positive value. A non-zero drop also represents a reset followed by
    /// immediate use. Preserve the most recent detected start and derive the
    /// seven-day boundary from it.
    private func inferredSevenDayReset(from samples: [ClaudeDesktopUsageSample]) -> Date? {
        var windowStartedAt: Date?
        var previousUsage: Double?

        for sample in samples {
            guard let usage = sample.sevenDay else { continue }
            defer { previousUsage = usage }

            if usage <= 0 {
                windowStartedAt = nil
                continue
            }

            if let previousUsage, previousUsage <= 0 || usage < previousUsage {
                windowStartedAt = sample.observedAt
            }
        }

        guard let windowStartedAt else { return nil }
        let reset = windowStartedAt.addingTimeInterval(7 * 24 * 60 * 60)
        return reset > Date() ? reset : nil
    }

    private func futureResetTimestamp(_ timestamp: Double?) -> Double? {
        guard let timestamp, timestamp > Date().timeIntervalSince1970 else {
            return nil
        }
        return timestamp
    }

    private func loadDailyUsage() -> [DailyUsage] {
        let metrics = claudeDirectory.appendingPathComponent("metrics/costs.jsonl")
        let metricUsage = aggregateMetricsFile(metrics) ?? []
        let transcriptUsage = aggregateTranscripts()

        // Some Claude Code versions leave costs.jsonl behind or append entries
        // whose token counts are zero. Never let that stale source hide newer,
        // richer transcript usage. The sources describe the same activity, so
        // choose the more complete value per day instead of summing both.
        var byDay = Dictionary(uniqueKeysWithValues: metricUsage.map { ($0.date, $0) })
        for usage in transcriptUsage {
            if let existing = byDay[usage.date], existing.tokens.total > usage.tokens.total {
                continue
            }
            byDay[usage.date] = usage
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    private func aggregateMetricsFile(_ url: URL) -> [DailyUsage]? {
        let cutoff = historyCutoff
        guard let metadata = fileMetadata(url) else {
            metricCache = nil
            return nil
        }
        if let metricCache,
           metricCache.size == metadata.size,
           metricCache.modifiedAt == metadata.modifiedAt {
            return metricCache.usage.filter { $0.date >= cutoff }
        }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var buckets: [Date: TokenUsage] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(ClaudeMetricEntry.self, from: lineData),
                  let date = CodexUsageProvider.parseDate(entry.timestamp),
                  date >= cutoff else { continue }
            let day = calendar.startOfDay(for: date)
            buckets[day, default: .zero] = buckets[day, default: .zero] + entry.asUsage
        }
        let usage = buckets.map { DailyUsage(date: $0.key, provider: id, tokens: $0.value) }.sorted { $0.date < $1.date }
        metricCache = ClaudeMetricCache(size: metadata.size, modifiedAt: metadata.modifiedAt, usage: usage)
        return usage
    }

    private func aggregateTranscripts() -> [DailyUsage] {
        let projects = claudeDirectory.appendingPathComponent("projects", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: projects,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = historyCutoff
        var currentFiles = Set<URL>()

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let metadata = fileMetadata(url), metadata.modifiedAt >= cutoff else { continue }
            currentFiles.insert(url)
            if let existing = transcriptStates[url],
               existing.size == metadata.size,
               existing.modifiedAt == metadata.modifiedAt { continue }
            transcriptStates[url] = parseTranscriptChanges(
                in: url,
                metadata: metadata,
                cutoff: cutoff,
                previousState: transcriptStates[url]
            )
        }

        transcriptStates = transcriptStates.filter { currentFiles.contains($0.key) }
        var buckets: [Date: TokenUsage] = [:]
        var seenMessages = Set<String>()
        for state in transcriptStates.values {
            for (messageID, value) in state.messages
            where value.day >= cutoff && seenMessages.insert(messageID).inserted {
                buckets[value.day, default: .zero] = buckets[value.day, default: .zero] + value.usage
            }
            for (day, usage) in state.anonymousUsage where day >= cutoff {
                buckets[day, default: .zero] = buckets[day, default: .zero] + usage
            }
        }
        return buckets.map { DailyUsage(date: $0.key, provider: id, tokens: $0.value) }.sorted { $0.date < $1.date }
    }

    private var historyCutoff: Date {
        calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now()))
            ?? .distantPast
    }

    private func parseTranscriptChanges(
        in url: URL,
        metadata: ClaudeFileMetadata,
        cutoff: Date,
        previousState: ClaudeTranscriptFileState?
    ) -> ClaudeTranscriptFileState {
        var state = previousState ?? ClaudeTranscriptFileState()
        let wasRewritten = metadata.size < state.offset
            || (metadata.size == state.size && metadata.modifiedAt != state.modifiedAt)
        if wasRewritten { state = ClaudeTranscriptFileState() }

        let initialRead = state.offset == 0
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            state.size = metadata.size
            state.modifiedAt = metadata.modifiedAt
            return state
        }
        defer { try? handle.close() }

        do {
            let startOffset = initialRead
                ? try initialTranscriptOffset(
                    handle: handle,
                    size: metadata.size,
                    cutoff: cutoff
                )
                : state.offset
            guard metadata.size >= startOffset else { return state }
            try handle.seek(toOffset: startOffset)
            var incoming = try handle.readToEnd() ?? Data()
            // A tail read normally begins halfway through a JSON line. Drop
            // only that partial record; subsequent refreshes start at offset.
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

            for line in lines where !line.isEmpty {
                _ = consumeTranscript(Data(line), cutoff: cutoff, state: &state)
            }
            if let finalLine, !finalLine.isEmpty,
               !consumeTranscript(finalLine, cutoff: cutoff, state: &state) {
                state.remainder = finalLine
            }
            state.offset = metadata.size
        } catch {
            // Retain the last valid state and retry the unread bytes later.
        }

        state.size = metadata.size
        state.modifiedAt = metadata.modifiedAt
        return state
    }

    /// Claude transcripts are chronological JSONL files. Scan backwards until
    /// a timestamp older than the history window is found, then parse forward
    /// from that chunk so large files retain every recent usage record.
    private func initialTranscriptOffset(
        handle: FileHandle,
        size: UInt64,
        cutoff: Date
    ) throws -> UInt64 {
        let chunkSize = UInt64(transcriptScanChunkBytes)
        var chunkEnd = size

        while chunkEnd > 0 {
            let chunkStart = chunkEnd > chunkSize ? chunkEnd - chunkSize : 0
            try handle.seek(toOffset: chunkStart)
            var chunk = try handle.read(upToCount: Int(chunkEnd - chunkStart)) ?? Data()
            if chunkStart > 0, let newline = chunk.firstIndex(of: 0x0A) {
                chunk.removeSubrange(chunk.startIndex...newline)
            }

            let containsOlderEntry = chunk
                .split(separator: 0x0A)
                .contains { line in
                    guard let entry = try? JSONDecoder().decode(
                        ClaudeTimestampEntry.self,
                        from: Data(line)
                    ),
                    let date = CodexUsageProvider.parseDate(entry.timestamp) else {
                        return false
                    }
                    return date < cutoff
                }
            if containsOlderEntry || chunkStart == 0 { return chunkStart }
            chunkEnd = chunkStart
        }
        return 0
    }

    @discardableResult
    private func consumeTranscript(
        _ line: Data,
        cutoff: Date,
        state: inout ClaudeTranscriptFileState
    ) -> Bool {
        guard let entry = try? JSONDecoder().decode(ClaudeTranscriptEntry.self, from: line)
        else { return false }
        // Valid non-usage records are complete and must not be kept as a
        // partial final line.
        guard let usage = entry.message?.usage ?? entry.usage,
              let date = CodexUsageProvider.parseDate(entry.timestamp),
              date >= cutoff else { return true }

        let day = calendar.startOfDay(for: date)
        if let messageID = entry.message?.id {
            state.messages[messageID] = ClaudeDatedUsage(day: day, usage: usage.asUsage)
        } else {
            state.anonymousUsage[day, default: .zero] = state.anonymousUsage[day, default: .zero]
                + usage.asUsage
        }
        return true
    }

    private func fileMetadata(_ url: URL) -> ClaudeFileMetadata? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modifiedAt = values.contentModificationDate else { return nil }
        return ClaudeFileMetadata(size: UInt64(size), modifiedAt: modifiedAt)
    }
}

private struct ClaudeFileMetadata {
    let size: UInt64
    let modifiedAt: Date
}

private struct ClaudeMetricCache {
    let size: UInt64
    let modifiedAt: Date
    let usage: [DailyUsage]
}

private struct ClaudeDatedUsage {
    let day: Date
    let usage: TokenUsage
}

private struct ClaudeTranscriptFileState {
    var size: UInt64 = 0
    var modifiedAt: Date = .distantPast
    var offset: UInt64 = 0
    var remainder = Data()
    var messages: [String: ClaudeDatedUsage] = [:]
    var anonymousUsage: [Date: TokenUsage] = [:]
}

struct ClaudeStatusSnapshot: Decodable {
    let collectedAt: Double?
    let rateLimits: ClaudeRateLimits?
    let contextWindow: ClaudeContextWindow?
    let cost: ClaudeCost?

    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case rateLimits = "rate_limits"
        case contextWindow = "context_window"
        case cost
    }
}

struct ClaudeRateLimits: Decodable {
    let fiveHour: ClaudeRateWindow?
    let sevenDay: ClaudeRateWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct ClaudeRateWindow: Decodable {
    let usedPercentage: Double?
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

struct ClaudeContextWindow: Decodable {
    let currentUsage: ClaudeTokenValues?

    enum CodingKeys: String, CodingKey {
        case currentUsage = "current_usage"
    }
}

struct ClaudeCost: Decodable {
    let totalCostUSD: Double?

    enum CodingKeys: String, CodingKey {
        case totalCostUSD = "total_cost_usd"
    }
}

struct ClaudeTokenValues: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }

    var asUsage: TokenUsage {
        let cached = (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0)
        return TokenUsage(
            input: (inputTokens ?? 0) + cached,
            cachedInput: cached,
            output: outputTokens ?? 0,
            reasoningOutput: 0
        )
    }
}

struct ClaudeMetricEntry: Decodable {
    let timestamp: String?
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    var asUsage: TokenUsage {
        TokenUsage(input: inputTokens ?? 0, cachedInput: 0, output: outputTokens ?? 0, reasoningOutput: 0)
    }
}

struct ClaudeTranscriptEntry: Decodable {
    let timestamp: String?
    let usage: ClaudeTokenValues?
    let message: ClaudeMessage?
}

private struct ClaudeTimestampEntry: Decodable {
    let timestamp: String?
}

struct ClaudeMessage: Decodable {
    let id: String?
    let model: String?
    let usage: ClaudeTokenValues?
}

private struct ClaudeDesktopUsageHistory: Decodable {
    let samples: [ClaudeDesktopRawSample]
}

private struct ClaudeDesktopRawSample: Decodable {
    let timestamp: Double
    let usage: ClaudeDesktopUsage

    enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case usage = "u"
    }

    var normalized: ClaudeDesktopUsageSample? {
        guard usage.fiveHour != nil || usage.sevenDay != nil else { return nil }
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
        return ClaudeDesktopUsageSample(
            observedAt: Date(timeIntervalSince1970: seconds),
            fiveHour: usage.fiveHour,
            sevenDay: usage.sevenDay
        )
    }
}

private struct ClaudeDesktopUsage: Decodable {
    let fiveHour: Double?
    let sevenDay: Double?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "fh"
        case sevenDay = "sd"
    }
}

private struct ClaudeDesktopUsageSample {
    let observedAt: Date
    let fiveHour: Double?
    let sevenDay: Double?
    var fiveHourResetsAt: Date? = nil
    var sevenDayResetsAt: Date? = nil
}
