import Foundation

/// Reads MiniMax Code Desktop's cached `coding_plan/remains` response.
///
/// The Desktop response is the sole MiniMax source: this provider does not
/// inspect Claude Code transcripts, API keys, cookies, or conversation data.
actor MiniMaxUsageProvider: UsageProvider {
    nonisolated let id = ProviderID.miniMax

    private let cacheDirectory: URL
    private var fileStates: [URL: MiniMaxDesktopFileState] = [:]
    private let maximumCacheFileSize = 10 * 1_024 * 1_024

    init(cacheDirectory: URL = ProviderPaths.miniMaxDesktopCacheDirectory) {
        self.cacheDirectory = cacheDirectory
    }

    func load() async -> ProviderResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: cacheDirectory.path) else {
            return ProviderResult(
                snapshot: .empty(id, availability: .cliNotInstalled),
                dailyUsage: []
            )
        }

        let files = cacheFiles(fileManager: fileManager)
        let currentFiles = Set(files.map(\.url))
        fileStates = fileStates.filter { currentFiles.contains($0.key) }

        for file in files {
            if let existing = fileStates[file.url],
               existing.size == file.size,
               existing.modifiedAt == file.modifiedAt {
                continue
            }

            let sample: MiniMaxDesktopQuotaSample?
            if file.size <= maximumCacheFileSize,
               let data = try? Data(contentsOf: file.url, options: [.mappedIfSafe]),
               let response = Self.quotaResponse(from: data),
               let quota = response.preferredTextQuota {
                sample = MiniMaxDesktopQuotaSample(
                    quota: quota,
                    observedAt: file.modifiedAt
                )
            } else {
                sample = nil
            }
            fileStates[file.url] = MiniMaxDesktopFileState(
                size: file.size,
                modifiedAt: file.modifiedAt,
                sample: sample
            )
        }

        guard let latest = fileStates.values
            .compactMap(\.sample)
            .max(by: { $0.observedAt < $1.observedAt }) else {
            return ProviderResult(
                snapshot: .empty(id, availability: .waitingForFirstSample),
                dailyUsage: []
            )
        }

        var windows: [RateLimitWindow] = []
        if let remaining = latest.quota.currentIntervalRemainingPercent {
            windows.append(RateLimitWindow(
                kind: .short,
                label: L10n.text("5 小时", "5 hours"),
                usedPercentage: 100 - remaining,
                resetsAt: Self.date(fromMilliseconds: latest.quota.endTime),
                durationMinutes: 300
            ))
        }
        if let remaining = latest.quota.currentWeeklyRemainingPercent {
            windows.append(RateLimitWindow(
                kind: .long,
                label: L10n.text("本周", "This week"),
                usedPercentage: 100 - remaining,
                resetsAt: Self.date(fromMilliseconds: latest.quota.weeklyEndTime)
            ))
        }

        guard !windows.isEmpty else {
            return ProviderResult(
                snapshot: .empty(id, availability: .unsupportedFormat),
                dailyUsage: []
            )
        }

        let snapshot = UsageSnapshot(
            provider: id,
            windows: windows,
            todayTokens: nil,
            estimatedCostUSD: nil,
            observedAt: latest.observedAt,
            availability: .ready(lastUpdated: latest.observedAt)
        )
        return ProviderResult(snapshot: snapshot, dailyUsage: [])
    }

    private func cacheFiles(fileManager: FileManager) -> [MiniMaxCacheFile] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            ),
            values.isRegularFile == true,
            let size = values.fileSize,
            let modifiedAt = values.contentModificationDate else {
                return nil
            }
            return MiniMaxCacheFile(
                url: url,
                size: size,
                modifiedAt: modifiedAt
            )
        }
    }

    nonisolated static func quotaResponse(from data: Data) -> MiniMaxQuotaResponse? {
        let marker = Data(#"{"model_remains":["#.utf8)
        var searchStart = data.startIndex

        while searchStart < data.endIndex,
              let markerRange = data.range(
                of: marker,
                options: [],
                in: searchStart..<data.endIndex
              ) {
            if let json = completeJSONObject(in: data, startingAt: markerRange.lowerBound),
               let response = try? JSONDecoder().decode(
                MiniMaxQuotaResponse.self,
                from: json
               ),
               !response.modelRemains.isEmpty {
                return response
            }
            searchStart = markerRange.upperBound
        }
        return nil
    }

    private nonisolated static func completeJSONObject(
        in data: Data,
        startingAt start: Data.Index
    ) -> Data? {
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = start

        while index < data.endIndex {
            let byte = data[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if byte == 0x5C {
                    isEscaped = true
                } else if byte == 0x22 {
                    isInsideString = false
                }
            } else {
                if byte == 0x22 {
                    isInsideString = true
                } else if byte == 0x7B {
                    depth += 1
                } else if byte == 0x7D {
                    depth -= 1
                    if depth == 0 {
                        return data.subdata(in: start..<data.index(after: index))
                    }
                }
            }
            index = data.index(after: index)
        }
        return nil
    }

    private nonisolated static func date(fromMilliseconds value: Double?) -> Date? {
        guard let value else { return nil }
        return Date(timeIntervalSince1970: value / 1_000)
    }
}

struct MiniMaxQuotaResponse: Decodable {
    let modelRemains: [MiniMaxModelQuota]

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
    }

    var preferredTextQuota: MiniMaxModelQuota? {
        modelRemains.first {
            $0.modelName.localizedCaseInsensitiveCompare("general") == .orderedSame
        } ?? modelRemains.first {
            let name = $0.modelName.lowercased()
            return !name.contains("video")
                && !name.contains("image")
                && !name.contains("speech")
                && !name.contains("music")
        }
    }
}

struct MiniMaxModelQuota: Decodable {
    let modelName: String
    let endTime: Double?
    let weeklyEndTime: Double?
    let currentIntervalRemainingPercent: Double?
    let currentWeeklyRemainingPercent: Double?

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case endTime = "end_time"
        case weeklyEndTime = "weekly_end_time"
        case currentIntervalRemainingPercent = "current_interval_remaining_percent"
        case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
    }
}

private struct MiniMaxCacheFile {
    let url: URL
    let size: Int
    let modifiedAt: Date
}

private struct MiniMaxDesktopQuotaSample {
    let quota: MiniMaxModelQuota
    let observedAt: Date
}

private struct MiniMaxDesktopFileState {
    let size: Int
    let modifiedAt: Date
    let sample: MiniMaxDesktopQuotaSample?
}
