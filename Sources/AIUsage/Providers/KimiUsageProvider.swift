import Foundation

actor KimiUsageProvider: UsageProvider {
    nonisolated let id = ProviderID.kimiCode

    private let rootDirectory: URL
    private let desktopLogURLs: [URL]
    private let calendar: Calendar
    private let rateLimitLoader: @Sendable () async -> KimiRateLimitSample?
    private var fileStates: [URL: KimiFileState] = [:]
    private var desktopLogStates: [URL: KimiDesktopLogState] = [:]
    private let initialDesktopLogTailBytes: UInt64 = 1_048_576

    init(
        rootDirectory: URL = ProviderPaths.kimiDirectory,
        desktopLogURLs: [URL] = ProviderPaths.kimiDesktopLogURLs,
        calendar: Calendar = .current,
        rateLimitLoader: (@Sendable () async -> KimiRateLimitSample?)? = nil
    ) {
        self.rootDirectory = rootDirectory
        self.desktopLogURLs = desktopLogURLs
        self.calendar = calendar
        self.rateLimitLoader = rateLimitLoader ?? { await KimiUsageAPI.load() }
    }

    func load() async -> ProviderResult {
        let fileManager = FileManager.default
        async let remoteRateLimits = rateLimitLoader()
        let desktopUsage = loadDesktopUsage(fileManager: fileManager)
        let hasCodeDirectory = fileManager.fileExists(atPath: rootDirectory.path)
        let rateLimits = await remoteRateLimits
        guard hasCodeDirectory || desktopUsage != nil || rateLimits != nil else {
            return ProviderResult(
                snapshot: .empty(id, availability: .cliNotInstalled),
                dailyUsage: []
            )
        }

        let files = hasCodeDirectory ? wireFiles(fileManager: fileManager) : []
        guard !files.isEmpty || desktopUsage != nil || rateLimits != nil else {
            return ProviderResult(
                snapshot: .empty(id, availability: .waitingForFirstSample),
                dailyUsage: []
            )
        }

        let cutoff = calendar.date(
            byAdding: .day,
            value: -7,
            to: calendar.startOfDay(for: Date())
        ) ?? .distantPast
        let fileSet = Set(files)
        fileStates = fileStates.filter { fileSet.contains($0.key) }

        let metadataByFile = Dictionary(
            uniqueKeysWithValues: files.compactMap { url in
                fileMetadata(url).map { (url, $0) }
            }
        )
        let newestFile = files.max {
            (metadataByFile[$0]?.modifiedAt ?? .distantPast)
                < (metadataByFile[$1]?.modifiedAt ?? .distantPast)
        }

        for file in files {
            guard let metadata = metadataByFile[file] else { continue }
            let existing = fileStates[file]
            if existing == nil, file != newestFile, metadata.modifiedAt < cutoff {
                continue
            }
            guard existing?.size != metadata.size
                    || existing?.modifiedAt != metadata.modifiedAt else {
                continue
            }
            fileStates[file] = parseChanges(
                in: file,
                metadata: metadata,
                previousState: existing
            )
        }

        let samples = fileStates.values.flatMap { state in
            state.records + Array(state.legacyRecords.values)
        }
        let latestTokenUsage = samples.max(by: { $0.date < $1.date })
        guard latestTokenUsage != nil || desktopUsage != nil || rateLimits != nil else {
            return ProviderResult(
                snapshot: .empty(id, availability: .unsupportedFormat),
                dailyUsage: []
            )
        }

        var buckets: [Date: TokenUsage] = [:]
        for sample in samples where sample.date >= cutoff {
            let day = calendar.startOfDay(for: sample.date)
            buckets[day, default: .zero] = buckets[day, default: .zero] + sample.usage
        }

        let today = buckets[calendar.startOfDay(for: Date())]
        let observedAt = max(
            max(
                latestTokenUsage?.date ?? .distantPast,
                desktopUsage?.observedAt ?? .distantPast
            ),
            rateLimits?.observedAt ?? .distantPast
        )
        var windows: [RateLimitWindow] = []
        if let fiveHour = rateLimits?.fiveHour {
            windows.append(RateLimitWindow(
                kind: .short,
                label: L10n.text("5 小时", "5 hours"),
                usedPercentage: fiveHour.usedPercentage,
                resetsAt: fiveHour.resetsAt,
                durationMinutes: 300
            ))
        }
        if let weekly = rateLimits?.weekly {
            windows.append(RateLimitWindow(
                kind: .long,
                label: L10n.text("本周", "Weekly"),
                usedPercentage: weekly.usedPercentage,
                resetsAt: weekly.resetsAt,
                durationMinutes: 10_080
            ))
        }
        if let usage = desktopUsage {
            windows.append(
                RateLimitWindow(
                    kind: .long,
                    label: L10n.text("订阅总额度", "Subscription usage"),
                    usedPercentage: usage.usedPercentage,
                    resetsAt: usage.resetsAt,
                    resetTimePrecision: .day
                )
            )
        }
        let snapshot = UsageSnapshot(
            provider: id,
            windows: windows,
            todayTokens: today,
            estimatedCostUSD: nil,
            observedAt: observedAt,
            availability: .ready(lastUpdated: observedAt)
        )
        let daily = buckets.map {
            DailyUsage(date: $0.key, provider: id, tokens: $0.value)
        }
        .sorted { $0.date < $1.date }
        return ProviderResult(snapshot: snapshot, dailyUsage: daily)
    }

    private func loadDesktopUsage(fileManager: FileManager) -> KimiDesktopUsageSample? {
        let existingURLs = desktopLogURLs.filter { fileManager.fileExists(atPath: $0.path) }
        let existingSet = Set(existingURLs)
        desktopLogStates = desktopLogStates.filter { existingSet.contains($0.key) }

        for url in existingURLs {
            guard let metadata = fileMetadata(url) else { continue }
            let existing = desktopLogStates[url]
            guard existing?.size != metadata.size
                    || existing?.modifiedAt != metadata.modifiedAt else {
                continue
            }
            desktopLogStates[url] = parseDesktopLogChanges(
                in: url,
                metadata: metadata,
                previousState: existing
            )
        }

        return desktopLogStates.values
            .compactMap(\.latest)
            .max { $0.observedAt < $1.observedAt }
    }

    private func parseDesktopLogChanges(
        in url: URL,
        metadata: KimiFileMetadata,
        previousState: KimiDesktopLogState?
    ) -> KimiDesktopLogState {
        var state = previousState ?? KimiDesktopLogState()
        let wasRewritten = metadata.size < state.offset
            || (metadata.size == state.size && metadata.modifiedAt != state.modifiedAt)
        if wasRewritten {
            state = KimiDesktopLogState()
        }

        let initialRead = state.offset == 0
        let startOffset = initialRead && metadata.size > initialDesktopLogTailBytes
            ? metadata.size - initialDesktopLogTailBytes
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
            if initialRead,
               startOffset > 0,
               let newline = incoming.firstIndex(of: 0x0A) {
                incoming.removeSubrange(incoming.startIndex...newline)
            }

            var combined = state.remainder
            combined.append(incoming)
            var lines = combined.split(
                separator: 0x0A,
                omittingEmptySubsequences: false
            )
            var finalLine: Data?
            if combined.last != 0x0A, let final = lines.popLast() {
                finalLine = Data(final)
            }
            state.remainder = Data()

            for rawLine in lines where !rawLine.isEmpty {
                _ = consumeDesktopLogLine(
                    Data(rawLine),
                    fallbackDate: metadata.modifiedAt,
                    state: &state
                )
            }
            if let finalLine, !finalLine.isEmpty {
                let consumed = consumeDesktopLogLine(
                    finalLine,
                    fallbackDate: metadata.modifiedAt,
                    state: &state
                )
                if !consumed {
                    // Keep a possibly partial last line until the writer adds
                    // its newline or remaining bytes.
                    state.remainder = finalLine
                }
            }
            state.offset = metadata.size
        } catch {
            // Preserve the last valid sample and retry when the log changes.
        }

        state.size = metadata.size
        state.modifiedAt = metadata.modifiedAt
        return state
    }

    private func consumeDesktopLogLine(
        _ data: Data,
        fallbackDate: Date,
        state: inout KimiDesktopLogState
    ) -> Bool {
        guard let line = String(data: data, encoding: .utf8),
              let sample = Self.desktopUsage(from: line, fallbackDate: fallbackDate) else {
            return false
        }
        if state.latest == nil || sample.observedAt >= state.latest!.observedAt {
            state.latest = sample
        }
        return true
    }

    nonisolated static func desktopUsage(
        from line: String,
        fallbackDate: Date
    ) -> KimiDesktopUsageSample? {
        guard line.contains("[SubscriptionManager]"),
              line.contains("refreshed(sub):"),
              let rawRatio = field(named: "omniRatio", in: line),
              let ratio = Double(rawRatio) else {
            return nil
        }

        let usedPercentage = ratio <= 1 ? ratio * 100 : ratio
        let resetValue = field(named: "resetAt", in: line)
        let resetsAt = resetValue.flatMap { $0 == "null" ? nil : date(from: $0) }
        return KimiDesktopUsageSample(
            usedPercentage: usedPercentage,
            resetsAt: resetsAt,
            observedAt: logDate(from: line) ?? fallbackDate
        )
    }

    private nonisolated static func field(named name: String, in line: String) -> String? {
        guard let range = line.range(of: "\(name)=") else { return nil }
        let suffix = line[range.upperBound...]
        return String(suffix.prefix { !$0.isWhitespace })
    }

    private nonisolated static func logDate(from line: String) -> Date? {
        guard line.first == "[",
              let closingBracket = line.firstIndex(of: "]") else {
            return nil
        }
        let value = String(line[line.index(after: line.startIndex)..<closingBracket])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.date(from: value)
    }

    private func parseChanges(
        in url: URL,
        metadata: KimiFileMetadata,
        previousState: KimiFileState?
    ) -> KimiFileState {
        var state = previousState ?? KimiFileState()
        let wasRewritten = metadata.size < state.offset
            || (metadata.size == state.size && metadata.modifiedAt != state.modifiedAt)
        if wasRewritten {
            state = KimiFileState()
        }

        guard metadata.size >= state.offset,
              let handle = try? FileHandle(forReadingFrom: url) else {
            state.size = metadata.size
            state.modifiedAt = metadata.modifiedAt
            return state
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.offset)
            let incoming = try handle.readToEnd() ?? Data()
            var combined = state.remainder
            combined.append(incoming)
            var lines = combined.split(
                separator: 0x0A,
                omittingEmptySubsequences: false
            )
            var finalLine: Data?
            if combined.last != 0x0A, let final = lines.popLast() {
                finalLine = Data(final)
            }
            state.remainder = Data()

            for rawLine in lines where !rawLine.isEmpty {
                _ = consume(Data(rawLine), fallbackDate: metadata.modifiedAt, state: &state)
            }
            if let finalLine,
               !finalLine.isEmpty,
               !consume(finalLine, fallbackDate: metadata.modifiedAt, state: &state) {
                state.remainder = finalLine
            }
            state.offset = metadata.size
        } catch {
            // Preserve the last valid state and retry the changed file later.
        }

        state.size = metadata.size
        state.modifiedAt = metadata.modifiedAt
        return state
    }

    @discardableResult
    private func consume(
        _ line: Data,
        fallbackDate: Date,
        state: inout KimiFileState
    ) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: line),
              let envelope = object as? [String: Any] else {
            return false
        }

        if envelope["type"] as? String == "usage.record",
           let rawUsage = envelope["usage"] as? [String: Any],
           let usage = Self.tokenUsage(from: rawUsage) {
            state.records.append(KimiUsageSample(
                date: Self.date(from: envelope["time"]) ?? fallbackDate,
                usage: usage
            ))
            return true
        }

        guard let message = envelope["message"] as? [String: Any],
              message["type"] as? String == "StatusUpdate",
              let payload = message["payload"] as? [String: Any],
              let rawUsage = payload["token_usage"] as? [String: Any],
              let usage = Self.tokenUsage(from: rawUsage) else {
            // This is a complete Kimi wire event that does not carry usage.
            return true
        }

        let date = Self.date(from: envelope["timestamp"]) ?? fallbackDate
        let messageID = payload["message_id"] as? String
            ?? "anonymous-\(state.anonymousLegacySequence)"
        if payload["message_id"] == nil {
            state.anonymousLegacySequence += 1
        }
        state.legacyRecords[messageID] = KimiUsageSample(date: date, usage: usage)
        return true
    }

    private func wireFiles(fileManager: FileManager) -> [URL] {
        let sessions = rootDirectory.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: sessions,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.lastPathComponent == "wire.jsonl" else {
                return nil
            }
            return url
        }
    }

    private func fileMetadata(_ url: URL) -> KimiFileMetadata? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let modifiedAt = attributes[.modificationDate] as? Date else {
            return nil
        }
        return KimiFileMetadata(size: size.uint64Value, modifiedAt: modifiedAt)
    }

    private static func tokenUsage(from value: [String: Any]) -> TokenUsage? {
        let cacheRead = integer(
            in: value,
            keys: [
                "inputCacheRead",
                "input_cache_read",
                "cache_read_input_tokens",
                "cache_read_tokens"
            ]
        )
        let cacheCreation = integer(
            in: value,
            keys: [
                "inputCacheCreation",
                "input_cache_creation",
                "cache_creation_input_tokens"
            ]
        )
        let cached = cacheRead + cacheCreation
        let input: Int
        if let prompt = optionalInteger(in: value, keys: ["prompt_tokens"]) {
            // OpenAI-compatible prompt_tokens already includes its cached subset.
            input = prompt
        } else {
            input = integer(
                in: value,
                keys: ["inputOther", "input_other", "input_tokens"]
            ) + cached
        }
        let output = integer(
            in: value,
            keys: ["output", "output_tokens", "completion_tokens"]
        )
        let cachedSubset = optionalInteger(in: value, keys: ["cached_tokens"]) ?? cached

        guard input > 0 || output > 0 || cachedSubset > 0 else {
            return nil
        }
        return TokenUsage(
            input: input,
            cachedInput: cachedSubset,
            output: output,
            reasoningOutput: 0
        )
    }

    private static func integer(in value: [String: Any], keys: [String]) -> Int {
        optionalInteger(in: value, keys: keys) ?? 0
    }

    private static func optionalInteger(
        in value: [String: Any],
        keys: [String]
    ) -> Int? {
        for key in keys {
            if let number = value[key] as? NSNumber {
                return number.intValue
            }
            if let string = value[key] as? String, let number = Int(string) {
                return number
            }
        }
        return nil
    }

    private nonisolated static func date(from value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1_000 : raw)
        }
        if let string = value as? String {
            if let raw = Double(string) {
                return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1_000 : raw)
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
        }
        return nil
    }
}

private struct KimiFileMetadata {
    let size: UInt64
    let modifiedAt: Date
}

private struct KimiFileState {
    var size: UInt64 = 0
    var modifiedAt: Date = .distantPast
    var offset: UInt64 = 0
    var remainder = Data()
    var records: [KimiUsageSample] = []
    var legacyRecords: [String: KimiUsageSample] = [:]
    var anonymousLegacySequence = 0
}

private struct KimiUsageSample {
    let date: Date
    let usage: TokenUsage
}

private struct KimiDesktopLogState {
    var size: UInt64 = 0
    var modifiedAt: Date = .distantPast
    var offset: UInt64 = 0
    var remainder = Data()
    var latest: KimiDesktopUsageSample?
}

struct KimiDesktopUsageSample {
    let usedPercentage: Double
    let resetsAt: Date?
    let observedAt: Date
}
