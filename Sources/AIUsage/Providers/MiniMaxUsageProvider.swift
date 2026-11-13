import Foundation
import Compression
import zlib

/// Reads MiniMax Code Desktop's cached subscription responses.
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
               let quota = response.preferredTextQuota,
               quota.intervalUsedPercentage != nil || quota.weeklyUsedPercentage != nil {
                sample = MiniMaxDesktopQuotaSample(
                    quota: quota,
                    observedAt: file.modifiedAt,
                    isStale: false
                )
            } else {
                // Chromium may be replacing this file during refresh. Retain the
                // last decoded sample, with its original timestamp and stale flag.
                sample = fileStates[file.url]?.sample.map {
                    MiniMaxDesktopQuotaSample(quota: $0.quota, observedAt: $0.observedAt, isStale: true)
                }
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
        if let used = latest.quota.intervalUsedPercentage {
            windows.append(RateLimitWindow(
                kind: .short,
                label: L10n.text("5 小时", "5 hours"),
                usedPercentage: used,
                resetsAt: latest.quota.isIntervalUnlimited ? nil : Self.date(fromMilliseconds: latest.quota.endTime),
                durationMinutes: 300,
                isUnlimited: latest.quota.isIntervalUnlimited
            ))
        }
        if let used = latest.quota.weeklyUsedPercentage {
            windows.append(RateLimitWindow(
                kind: .long,
                label: L10n.text("本周", "This week"),
                usedPercentage: used,
                resetsAt: latest.quota.isWeeklyUnlimited ? nil : Self.date(fromMilliseconds: latest.quota.weeklyEndTime),
                durationMinutes: 10_080,
                isUnlimited: latest.quota.isWeeklyUnlimited
            ))
        }

        let snapshot = UsageSnapshot(
            provider: id,
            windows: windows,
            todayTokens: nil,
            estimatedCostUSD: nil,
            observedAt: latest.observedAt,
            availability: latest.isStale || windows.contains(where: { !$0.isUnlimited && ($0.resetsAt.map { $0 <= Date() } ?? false) })
                ? .stale(lastUpdated: latest.observedAt) : .ready(lastUpdated: latest.observedAt)
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
        let initialMagic = Data([0x30, 0x5C, 0x72, 0xA7, 0x1B, 0x6D, 0xFB, 0xFC])
        if data.starts(with: initialMagic) {
            guard let body = cachedResponseBody(from: data) else { return nil }
            return decodeResponse(body)
        }
        return legacyQuotaResponse(from: data)
    }

    /// Chromium Simple Cache v5 stores body, EOF, headers, optional key hash,
    /// then the final EOF. Read sizes from the footer instead of guessing where
    /// compressed bytes end. Only subscription endpoint bodies are decompressed.
    private nonisolated static func cachedResponseBody(from data: Data) -> Data? {
        let recordSize = 24
        let finalMagic = Data([0xD8, 0x41, 0x0D, 0x97, 0x45, 0x6F, 0xFA, 0xF4])
        guard data.count >= recordSize * 3 else { return nil }
        func uint32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
        }
        guard uint32(8) == 5 else { return nil }
        let bodyStart = recordSize + Int(uint32(12))
        let finalEOF = data.count - recordSize
        guard bodyStart <= finalEOF,
              data[finalEOF..<(finalEOF + 8)] == finalMagic else { return nil }
        let key = String(decoding: data[recordSize..<bodyStart], as: UTF8.self)
        guard key.contains("/backend/account/token_plan/remains_percent")
                || key.contains("/v1/api/openplatform/coding_plan/remains") else { return nil }
        let keyHashSize = uint32(finalEOF + 8) & 2 != 0 ? 32 : 0
        let headersEnd = finalEOF - keyHashSize
        let headersStart = headersEnd - Int(uint32(finalEOF + 16))
        let bodyEnd = headersStart - recordSize
        guard bodyEnd >= bodyStart, headersEnd >= headersStart,
              data[bodyEnd..<(bodyEnd + 8)] == finalMagic else { return nil }
        let body = data.subdata(in: bodyStart..<bodyEnd)
        if uint32(bodyEnd + 8) & 1 != 0 {
            let checksum = body.withUnsafeBytes {
                crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))
            }
            guard UInt32(checksum) == uint32(bodyEnd + 12) else { return nil }
        }
        let headers = String(decoding: data[headersStart..<headersEnd], as: UTF8.self)
        let encoding = headers.components(separatedBy: "\0")
            .first { $0.lowercased().hasPrefix("content-encoding:") }?
            .split(separator: ":", maxSplits: 1).last?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard encoding == nil || encoding == "identity" || encoding == "br" else { return nil }
        guard encoding == "br" else { return body }
        let limit = 1_048_576
        var decoded = [UInt8](repeating: 0, count: limit)
        let count = body.withUnsafeBytes { bytes in
            guard let source = bytes.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&decoded, limit, source, bytes.count, nil, COMPRESSION_BROTLI)
        }
        guard count > 0, count < limit else { return nil }
        return Data(decoded.prefix(count))
    }

    private nonisolated static func decodeResponse(_ data: Data) -> MiniMaxQuotaResponse? {
        guard let response = try? JSONDecoder().decode(MiniMaxQuotaResponse.self, from: data),
              !response.modelRemains.isEmpty, (response.baseResponse?.statusCode ?? 0) == 0 else { return nil }
        return response
    }

    private nonisolated static func legacyQuotaResponse(from data: Data) -> MiniMaxQuotaResponse? {
        let marker = Data(#""model_remains""#.utf8)
        var searchStart = data.startIndex

        while searchStart < data.endIndex,
              let markerRange = data.range(
                of: marker,
                options: [],
                in: searchStart..<data.endIndex
              ) {
            for objectStart in objectStarts(
                in: data,
                before: markerRange.lowerBound
            ) {
                guard let json = completeJSONObject(in: data, startingAt: objectStart),
                      let response = decodeResponse(json) else {
                    continue
                }
                return response
            }
            searchStart = markerRange.upperBound
        }
        return nil
    }

    /// Chromium cache entries contain headers and other binary data around the
    /// response body. Walk backwards from the quota key and try nearby object
    /// boundaries so JSON whitespace and top-level field order remain flexible.
    private nonisolated static func objectStarts(
        in data: Data,
        before markerStart: Data.Index
    ) -> [Data.Index] {
        let maximumLookBehind = 64 * 1_024
        let lowerBound = max(data.startIndex, markerStart - maximumLookBehind)
        var candidates: [Data.Index] = []
        var index = markerStart

        while index > lowerBound, candidates.count < 128 {
            index = data.index(before: index)
            if data[index] == 0x7B {
                candidates.append(index)
            }
        }
        return candidates
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
    let baseResponse: MiniMaxBaseResponse?

    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResponse = "base_resp"
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
    let currentIntervalUsedPercent: Double?
    let currentWeeklyUsedPercent: Double?
    let currentIntervalStatus: Int?
    let currentWeeklyStatus: Int?

    var isIntervalUnlimited: Bool { currentIntervalStatus == 3 }
    var isWeeklyUnlimited: Bool { currentWeeklyStatus == 3 }
    var intervalUsedPercentage: Double? {
        isIntervalUnlimited ? 0 : currentIntervalUsedPercent ?? currentIntervalRemainingPercent.map { 100 - $0 }
    }
    var weeklyUsedPercentage: Double? {
        isWeeklyUnlimited ? 0 : currentWeeklyUsedPercent ?? currentWeeklyRemainingPercent.map { 100 - $0 }
    }

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case endTime = "end_time"
        case weeklyEndTime = "weekly_end_time"
        case currentIntervalRemainingPercent = "current_interval_remaining_percent"
        case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
        case currentIntervalUsedPercent = "current_interval_used_percent"
        case currentWeeklyUsedPercent = "current_weekly_used_percent"
        case currentIntervalStatus = "current_interval_status"
        case currentWeeklyStatus = "current_weekly_status"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        modelName = try values.decode(String.self, forKey: .modelName)
        endTime = try values.decodeIfPresent(Double.self, forKey: .endTime)
        weeklyEndTime = try values.decodeIfPresent(Double.self, forKey: .weeklyEndTime)
        func percentage(_ key: CodingKeys) -> Double? {
            let value: Double?
            if let number = try? values.decode(Double.self, forKey: key) { value = number }
            else if let text = try? values.decode(String.self, forKey: key) {
                var number = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if number.hasSuffix("%") { number.removeLast() }
                value = Double(number.trimmingCharacters(in: .whitespacesAndNewlines))
            } else { value = nil }
            return value.flatMap { $0.isFinite ? $0 : nil }
        }
        currentIntervalRemainingPercent = percentage(.currentIntervalRemainingPercent)
        currentWeeklyRemainingPercent = percentage(.currentWeeklyRemainingPercent)
        currentIntervalUsedPercent = percentage(.currentIntervalUsedPercent)
        currentWeeklyUsedPercent = percentage(.currentWeeklyUsedPercent)
        currentIntervalStatus = try values.decodeIfPresent(Int.self, forKey: .currentIntervalStatus)
        currentWeeklyStatus = try values.decodeIfPresent(Int.self, forKey: .currentWeeklyStatus)
    }
}

struct MiniMaxBaseResponse: Decodable {
    let statusCode: Int?
    enum CodingKeys: String, CodingKey { case statusCode = "status_code" }
}

private struct MiniMaxCacheFile {
    let url: URL
    let size: Int
    let modifiedAt: Date
}

private struct MiniMaxDesktopQuotaSample {
    let quota: MiniMaxModelQuota
    let observedAt: Date
    let isStale: Bool
}

private struct MiniMaxDesktopFileState {
    let size: Int
    let modifiedAt: Date
    let sample: MiniMaxDesktopQuotaSample?
}
