import Foundation
import Darwin

actor AntigravityUsageProvider: UsageProvider {
    nonisolated let id = ProviderID.antigravity

    private let rootDirectories: [URL]
    private let appBundleURL: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let quotaLoader: @Sendable () async -> AntigravityQuotaSummary?
    private var fileStates: [URL: AntigravityTranscriptFileState] = [:]
    private var cachedQuota: CachedQuota?

    init(
        rootDirectories: [URL] = ProviderPaths.antigravityDirectories,
        appBundleURL: URL = ProviderPaths.antigravityAppBundleURL,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        quotaLoader: (@Sendable () async -> AntigravityQuotaSummary?)? = nil
    ) {
        self.rootDirectories = rootDirectories
        self.appBundleURL = appBundleURL
        self.calendar = calendar
        self.now = now
        self.quotaLoader = quotaLoader ?? {
            await AntigravityQuotaClient.load(from: rootDirectories)
        }
    }

    init(
        rootDirectory: URL,
        appBundleURL: URL? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        quotaLoader: @escaping @Sendable () async -> AntigravityQuotaSummary? = { nil }
    ) {
        let missingApp = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-antigravity-app-\(UUID().uuidString)")
        self.init(
            rootDirectories: [rootDirectory],
            appBundleURL: appBundleURL ?? missingApp,
            calendar: calendar,
            now: now,
            quotaLoader: quotaLoader
        )
    }

    func load() async -> ProviderResult {
        let fileManager = FileManager.default
        let currentNow = now()
        async let remoteQuota = quotaLoader()

        let existingRoots = rootDirectories.filter { fileManager.fileExists(atPath: $0.path) }
        let hasAppBundle = fileManager.fileExists(atPath: appBundleURL.path)
        let files = existingRoots.flatMap { transcriptFiles(in: $0, fileManager: fileManager) }

        let cutoff = calendar.date(
            byAdding: .day,
            value: -7,
            to: calendar.startOfDay(for: currentNow)
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

        let allSamples = fileStates.values.flatMap { state in
            Array(state.steps.values) + state.anonymousSteps
        }
        let latestTokenSample = allSamples.max { $0.date < $1.date }

        var buckets: [Date: TokenUsage] = [:]
        for sample in allSamples where sample.date >= cutoff {
            let day = calendar.startOfDay(for: sample.date)
            buckets[day, default: .zero] = buckets[day, default: .zero] + sample.usage
        }

        let liveQuota = await remoteQuota
        if let liveQuota, liveQuota.hasBuckets {
            cachedQuota = CachedQuota(summary: liveQuota, observedAt: currentNow)
        }

        let windows = cachedQuota.map {
            Self.makeWindows(from: $0.summary, now: currentNow)
        } ?? []

        guard !existingRoots.isEmpty || hasAppBundle || cachedQuota != nil else {
            return ProviderResult(
                snapshot: .empty(id, availability: .cliNotInstalled),
                dailyUsage: []
            )
        }

        guard !files.isEmpty || cachedQuota != nil else {
            return ProviderResult(
                snapshot: .empty(id, availability: .waitingForFirstSample),
                dailyUsage: []
            )
        }

        guard latestTokenSample != nil || cachedQuota != nil else {
            return ProviderResult(
                snapshot: .empty(id, availability: .unsupportedFormat),
                dailyUsage: []
            )
        }

        let today = buckets[calendar.startOfDay(for: currentNow)]
        let observedAt = max(
            latestTokenSample?.date ?? .distantPast,
            cachedQuota?.observedAt ?? .distantPast
        )
        let allQuotaExpired = cachedQuota != nil && windows.isEmpty
        let availability: ProviderAvailability = allQuotaExpired
            ? .stale(lastUpdated: observedAt)
            : .ready(lastUpdated: observedAt)

        let snapshot = UsageSnapshot(
            provider: id,
            windows: windows,
            todayTokens: today,
            estimatedCostUSD: nil,
            observedAt: observedAt,
            availability: availability
        )
        let daily = buckets.map {
            DailyUsage(date: $0.key, provider: id, tokens: $0.value)
        }.sorted { $0.date < $1.date }
        return ProviderResult(snapshot: snapshot, dailyUsage: daily)
    }

    private func parseChanges(
        in url: URL,
        metadata: AntigravityFileMetadata,
        previousState: AntigravityTranscriptFileState?
    ) -> AntigravityTranscriptFileState {
        var state = previousState ?? AntigravityTranscriptFileState()
        if metadata.size < state.cursor.offset
            || (metadata.size == state.size && metadata.modifiedAt != state.modifiedAt) {
            state = AntigravityTranscriptFileState()
        }
        do {
            let cursor = try IncrementalLineReader.read(
                from: url,
                size: metadata.size,
                cursor: state.cursor
            ) {
                consume($0, fallbackDate: metadata.modifiedAt, state: &state)
            }
            state.cursor = cursor
            state.size = metadata.size
            state.modifiedAt = metadata.modifiedAt
            return state
        } catch {
            return previousState ?? state
        }
    }

    @discardableResult
    private func consume(
        _ line: Data,
        fallbackDate: Date,
        state: inout AntigravityTranscriptFileState
    ) -> Bool {
        guard let step = try? JSONDecoder().decode(AntigravityTranscriptStep.self, from: line) else {
            return false
        }
        guard let usage = step.asUsage else {
            // Non-usage steps (such as USER_INPUT or GENERIC) are complete JSON lines.
            return true
        }
        let date = ISODateParser.parse(step.createdAt) ?? fallbackDate
        let sample = AntigravityDatedUsage(date: date, usage: usage)
        if let stepIndex = step.stepIndex {
            state.steps[stepIndex] = sample
        } else {
            state.anonymousSteps.append(sample)
        }
        return true
    }

    private func transcriptFiles(in rootDirectory: URL, fileManager: FileManager) -> [URL] {
        var urls: [URL] = []
        let brainDirectory = rootDirectory.appendingPathComponent("brain", isDirectory: true)
        if let conversations = try? fileManager.contentsOfDirectory(
            at: brainDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for conversation in conversations {
                let systemTranscript = conversation
                    .appendingPathComponent(".system_generated/logs/transcript.jsonl")
                if fileManager.fileExists(atPath: systemTranscript.path) {
                    urls.append(systemTranscript)
                }
                let directTranscript = conversation.appendingPathComponent("transcript.jsonl")
                if fileManager.fileExists(atPath: directTranscript.path) {
                    urls.append(directTranscript)
                }
            }
        }
        let rootTranscript = rootDirectory.appendingPathComponent("transcript.jsonl")
        if fileManager.fileExists(atPath: rootTranscript.path) {
            urls.append(rootTranscript)
        }
        return urls
    }

    private func fileMetadata(_ url: URL) -> AntigravityFileMetadata? {
        guard let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        ),
        let size = values.fileSize,
        let modifiedAt = values.contentModificationDate else {
            return nil
        }
        return AntigravityFileMetadata(size: UInt64(size), modifiedAt: modifiedAt)
    }

    nonisolated static func makeWindows(
        from summary: AntigravityQuotaSummary,
        now: Date = Date()
    ) -> [RateLimitWindow] {
        struct FlatBucket {
            let groupName: String?
            let bucket: AntigravityQuotaBucket
        }

        var entries: [FlatBucket] = []
        for group in summary.groups {
            for bucket in group.buckets where bucket.disabled != true {
                entries.append(FlatBucket(groupName: group.displayName, bucket: bucket))
            }
        }
        if entries.isEmpty {
            for bucket in summary.buckets where bucket.disabled != true {
                entries.append(FlatBucket(groupName: nil, bucket: bucket))
            }
        }

        let validEntries = entries.filter { $0.bucket.usedPercentage != nil }
        guard !validEntries.isEmpty else { return [] }

        let primaryIndex = validEntries.firstIndex {
            $0.bucket.bucketId?.lowercased() == "gemini-5h"
        } ?? validEntries.firstIndex {
            $0.bucket.isFiveHourWindow
                && ($0.groupName?.localizedCaseInsensitiveContains("gemini") == true)
                && !($0.groupName?.localizedCaseInsensitiveContains("argon") == true)
        } ?? validEntries.firstIndex {
            $0.bucket.isFiveHourWindow
        }

        var windows: [RateLimitWindow] = []
        if let primaryIndex {
            let primary = validEntries[primaryIndex]
            let resetDate = ISODateParser.parse(primary.bucket.resetTime)
            if resetDate.map({ $0 > now }) ?? true,
               let used = primary.bucket.usedPercentage {
                windows.append(
                    RateLimitWindow(
                        kind: .short,
                        label: L10n.text("5 小时", "5 hours"),
                        usedPercentage: used,
                        resetsAt: resetDate,
                        durationMinutes: 300
                    )
                )
            }
        }

        for (index, entry) in validEntries.enumerated() where index != primaryIndex {
            let resetDate = ISODateParser.parse(entry.bucket.resetTime)
            guard resetDate.map({ $0 > now }) ?? true,
                  let used = entry.bucket.usedPercentage else {
                continue
            }
            windows.append(
                RateLimitWindow(
                    kind: .long,
                    label: secondaryWindowLabel(groupName: entry.groupName, bucket: entry.bucket),
                    usedPercentage: used,
                    resetsAt: resetDate,
                    durationMinutes: entry.bucket.durationMinutes
                )
            )
        }
        return windows
    }

    private nonisolated static func secondaryWindowLabel(
        groupName: String?,
        bucket: AntigravityQuotaBucket
    ) -> String {
        let bucketID = bucket.bucketId?.lowercased() ?? ""
        if bucketID == "gemini-weekly" {
            return L10n.text("本周", "Weekly")
        }
        if bucketID.contains("argon") && bucket.isWeeklyWindow {
            return L10n.text("Argon · 本周", "Argon · Weekly")
        }
        if bucketID == "3p-5h" {
            return L10n.text("Claude/GPT · 5 小时", "Claude/GPT · 5 hours")
        }
        if bucketID == "3p-weekly" {
            return L10n.text("Claude/GPT · 本周", "Claude/GPT · Weekly")
        }

        let periodLabel: String
        if bucket.isFiveHourWindow {
            periodLabel = L10n.text("5 小时", "5 hours")
        } else if bucket.isWeeklyWindow {
            periodLabel = L10n.text("本周", "Weekly")
        } else if let displayName = bucket.displayName, !displayName.isEmpty {
            periodLabel = displayName
        } else {
            periodLabel = L10n.text("额度", "Quota")
        }

        guard let groupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !groupName.isEmpty else {
            return periodLabel
        }
        let lowerGroup = groupName.lowercased()
        if lowerGroup == "gemini models" || lowerGroup == "gemini" {
            return periodLabel
        }
        if lowerGroup.contains("argon") {
            return "Argon · \(periodLabel)"
        }
        if lowerGroup.contains("claude") && lowerGroup.contains("gpt") {
            return "Claude/GPT · \(periodLabel)"
        }
        return "\(groupName) · \(periodLabel)"
    }
}

enum AntigravityQuotaClient {
    static func load(
        from rootDirectories: [URL] = ProviderPaths.antigravityDirectories
    ) async -> AntigravityQuotaSummary? {
        for endpoint in discoverEndpoints(in: rootDirectories) {
            if let summary = await requestQuotaSummary(from: endpoint) {
                return summary
            }
        }
        return nil
    }

    static func discoverEndpoints(
        in rootDirectories: [URL],
        fileManager: FileManager = .default,
        isProcessAlive: (Int32) -> Bool = defaultProcessCheck
    ) -> [AntigravityServerEndpoint] {
        var candidates: [(endpoint: AntigravityServerEndpoint, modifiedAt: Date)] = []

        for root in rootDirectories {
            let daemonDir = root.appendingPathComponent("daemon", isDirectory: true)
            guard let urls = try? fileManager.contentsOfDirectory(
                at: daemonDir,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let discovery = try? JSONDecoder().decode(AntigravityDiscoveryFile.self, from: data),
                      let port = discovery.httpPort,
                      port > 0,
                      let token = discovery.csrfToken,
                      !token.isEmpty else { continue }
                if let pid = discovery.pid, pid > 0, !isProcessAlive(pid) {
                    continue
                }
                let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                candidates.append((
                    AntigravityServerEndpoint(host: "127.0.0.1", port: port, csrfToken: token),
                    modifiedAt
                ))
            }
        }

        var ordered = candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .map(\.endpoint)

        let env = ProcessInfo.processInfo.environment
        if let address = env["ANTIGRAVITY_LS_ADDRESS"],
           let token = env["ANTIGRAVITY_CSRF_TOKEN"],
           !token.isEmpty,
           let endpoint = parseAddress(address, csrfToken: token),
           !ordered.contains(endpoint) {
            ordered.append(endpoint)
        }
        return ordered
    }

    private static func parseAddress(_ raw: String, csrfToken: String) -> AntigravityServerEndpoint? {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let port = Int(parts[1]),
              port > 0 else { return nil }
        let host = parts[0].lowercased() == "localhost" ? "127.0.0.1" : String(parts[0])
        guard host == "127.0.0.1" else { return nil }
        return AntigravityServerEndpoint(host: host, port: port, csrfToken: csrfToken)
    }

    private static func defaultProcessCheck(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func requestQuotaSummary(
        from endpoint: AntigravityServerEndpoint
    ) async -> AntigravityQuotaSummary? {
        guard let url = URL(
            string: "http://\(endpoint.host):\(endpoint.port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
        ) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = Data(#"{"forceRefresh":false}"#.utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return nil
        }
        return decodeQuotaSummary(from: data)
    }

    static func decodeQuotaSummary(from data: Data) -> AntigravityQuotaSummary? {
        if let envelope = try? JSONDecoder().decode(AntigravityQuotaEnvelope.self, from: data),
           let summary = envelope.response,
           summary.hasBuckets {
            return summary
        }
        if let direct = try? JSONDecoder().decode(AntigravityQuotaSummary.self, from: data),
           direct.hasBuckets {
            return direct
        }
        return nil
    }
}

struct AntigravityServerEndpoint: Equatable, Sendable {
    let host: String
    let port: Int
    let csrfToken: String
}

struct AntigravityDiscoveryFile: Decodable, Sendable {
    let pid: Int32?
    let httpsPort: Int?
    let httpPort: Int?
    let lsVersion: String?
    let csrfToken: String?
}

private struct AntigravityQuotaEnvelope: Decodable, Sendable {
    let response: AntigravityQuotaSummary?
}

struct AntigravityQuotaSummary: Decodable, Sendable {
    let description: String?
    let buckets: [AntigravityQuotaBucket]
    let groups: [AntigravityQuotaGroup]

    var hasBuckets: Bool {
        !buckets.isEmpty || groups.contains { !$0.buckets.isEmpty }
    }

    init(
        description: String? = nil,
        buckets: [AntigravityQuotaBucket] = [],
        groups: [AntigravityQuotaGroup] = []
    ) {
        self.description = description
        self.buckets = buckets
        self.groups = groups
    }

    enum CodingKeys: String, CodingKey {
        case description, buckets, groups
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        buckets = try values.decodeIfPresent([AntigravityQuotaBucket].self, forKey: .buckets) ?? []
        groups = try values.decodeIfPresent([AntigravityQuotaGroup].self, forKey: .groups) ?? []
    }
}

struct AntigravityQuotaGroup: Decodable, Sendable {
    let displayName: String?
    let description: String?
    let buckets: [AntigravityQuotaBucket]

    init(
        displayName: String?,
        description: String? = nil,
        buckets: [AntigravityQuotaBucket]
    ) {
        self.displayName = displayName
        self.description = description
        self.buckets = buckets
    }

    enum CodingKeys: String, CodingKey {
        case displayName
        case displayNameSnake = "display_name"
        case description
        case buckets
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName)
            ?? values.decodeIfPresent(String.self, forKey: .displayNameSnake)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        buckets = try values.decodeIfPresent([AntigravityQuotaBucket].self, forKey: .buckets) ?? []
    }
}

struct AntigravityQuotaBucket: Decodable, Sendable {
    let bucketId: String?
    let displayName: String?
    let description: String?
    let window: String?
    let remainingFraction: Double?
    let disabled: Bool?
    let resetTime: String?

    init(
        bucketId: String? = nil,
        displayName: String? = nil,
        description: String? = nil,
        window: String? = nil,
        remainingFraction: Double? = nil,
        disabled: Bool? = nil,
        resetTime: String? = nil
    ) {
        self.bucketId = bucketId
        self.displayName = displayName
        self.description = description
        self.window = window
        self.remainingFraction = remainingFraction
        self.disabled = disabled
        self.resetTime = resetTime
    }

    var usedPercentage: Double? {
        guard let remainingFraction, remainingFraction.isFinite else { return nil }
        let clampedRemaining = min(max(remainingFraction, 0), 1)
        return (1 - clampedRemaining) * 100
    }

    var isFiveHourWindow: Bool {
        let normalizedWindow = window?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedWindow == "5h" || normalizedWindow == "300m" {
            return true
        }
        return bucketId?.lowercased().hasSuffix("-5h") == true
    }

    var isWeeklyWindow: Bool {
        let normalizedWindow = window?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedWindow == "weekly" || normalizedWindow == "7d" {
            return true
        }
        return bucketId?.lowercased().hasSuffix("-weekly") == true
    }

    var durationMinutes: Int? {
        if isFiveHourWindow { return 300 }
        if isWeeklyWindow { return 10_080 }
        return nil
    }

    private struct RemainingOneof: Decodable {
        let `case`: String?
        let value: Double?
    }

    enum CodingKeys: String, CodingKey {
        case bucketId
        case bucketIdSnake = "bucket_id"
        case displayName
        case displayNameSnake = "display_name"
        case description
        case window
        case remainingFraction
        case remainingFractionSnake = "remaining_fraction"
        case remaining
        case disabled
        case resetTime
        case resetTimeSnake = "reset_time"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bucketId = try values.decodeIfPresent(String.self, forKey: .bucketId)
            ?? values.decodeIfPresent(String.self, forKey: .bucketIdSnake)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName)
            ?? values.decodeIfPresent(String.self, forKey: .displayNameSnake)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        window = try values.decodeIfPresent(String.self, forKey: .window)
        if let direct = try? values.decodeIfPresent(Double.self, forKey: .remainingFraction) {
            remainingFraction = direct
        } else if let snake = try? values.decodeIfPresent(Double.self, forKey: .remainingFractionSnake) {
            remainingFraction = snake
        } else if let oneof = try? values.decodeIfPresent(RemainingOneof.self, forKey: .remaining),
                  oneof.case == "remainingFraction" {
            remainingFraction = oneof.value
        } else {
            remainingFraction = nil
        }
        disabled = try values.decodeIfPresent(Bool.self, forKey: .disabled)
        resetTime = try values.decodeIfPresent(String.self, forKey: .resetTime)
            ?? values.decodeIfPresent(String.self, forKey: .resetTimeSnake)
    }
}

private struct CachedQuota {
    let summary: AntigravityQuotaSummary
    let observedAt: Date
}

private struct AntigravityFileMetadata {
    let size: UInt64
    let modifiedAt: Date
}

private struct AntigravityDatedUsage {
    let date: Date
    let usage: TokenUsage
}

private struct AntigravityTranscriptFileState {
    var size: UInt64 = 0
    var modifiedAt: Date = .distantPast
    var cursor = IncrementalLineReader.Cursor()
    var steps: [Int: AntigravityDatedUsage] = [:]
    var anonymousSteps: [AntigravityDatedUsage] = []
}

private struct AntigravityTranscriptStep: Decodable {
    let stepIndex: Int?
    let createdAt: String?
    let inputTokens: Int?
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case createdAt = "created_at"
        case inputTokens = "input_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheWriteTokens = "cache_write_tokens"
        case outputTokens = "output_tokens"
    }

    var asUsage: TokenUsage? {
        guard inputTokens != nil
                || cacheReadTokens != nil
                || cacheWriteTokens != nil
                || outputTokens != nil else {
            return nil
        }
        let cached = max(cacheReadTokens ?? 0, 0) + max(cacheWriteTokens ?? 0, 0)
        let input = max(inputTokens ?? 0, 0) + cached
        let output = max(outputTokens ?? 0, 0)
        guard input > 0 || output > 0 else { return nil }
        return TokenUsage(
            input: input,
            cachedInput: cached,
            output: output,
            reasoningOutput: 0
        )
    }
}
