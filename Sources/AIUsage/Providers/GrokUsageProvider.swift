import Foundation
import CryptoKit

actor GrokUsageProvider: UsageProvider {
    nonisolated let id = ProviderID.grok
    private let rootDirectory: URL
    private let now: @Sendable () -> Date
    private let reader: @Sendable (URL, Int) throws -> Data
    private var previous: Sample?

    init(
        rootDirectory: URL = ProviderPaths.grokBotCacheDirectory,
        now: @escaping @Sendable () -> Date = Date.init,
        reader: @escaping @Sendable (URL, Int) throws -> Data = GrokCacheFile.read
    ) {
        self.rootDirectory = rootDirectory
        self.now = now
        self.reader = reader
    }

    func load() async -> ProviderResult {
        let date = now()
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            previous = nil
            return empty(.cliNotInstalled)
        }
        guard let account = activeAccount() else {
            previous = nil
            return empty(.failed(L10n.text(
                "请登录 Grok Bot 并打开 Usage & Billing，以更新订阅周额度",
                "Sign in to Grok Bot and open Usage & Billing to update subscription usage."
            )))
        }
        if previous?.account != account { previous = nil }

        do {
            let key = GrokCacheFile.quotaKey(account: account)
            let data = try readSlice(key, limit: 65_536)
            let envelope = try JSONDecoder().decode(Envelope<QuotaCache>.self, from: data)
            guard activeAccount() == account else {
                previous = nil
                return empty(.failed(L10n.text("Grok 账号已变化，请刷新", "Grok account changed. Refresh to reload.")))
            }
            guard envelope.schemaVersion == 3 else {
                previous = nil
                return empty(.unsupportedFormat)
            }
            let cache = envelope.value
            guard cache.kind == "present", let reading = cache.reading else {
                previous = nil
                return empty(.failed(Self.refreshMessage))
            }
            let usage = reading.usage
            guard cache.selectedTeamId == nil, usage.readForTeamId == nil, usage.isTeamSeat != true else {
                previous = nil
                return empty(.failed(L10n.text(
                    "请在 Grok Bot 切换到个人订阅账号；暂不支持团队额度",
                    "Select a personal subscription in Grok Bot; team quotas are not supported."
                )))
            }
            guard usage.hasNonZeroIncludedLimit else {
                previous = nil
                return empty(.failed(L10n.text(
                    "当前 Grok 账号未提供订阅周额度，请在 Grok Bot 核对订阅状态",
                    "This Grok account has no included weekly quota. Check its subscription in Grok Bot."
                )))
            }
            guard usage.percentUsed.isFinite, usage.percentUsed >= 0,
                  reading.readAtMs.isFinite, reading.readAtMs > 0,
                  cache.expiresAtMs.isFinite, cache.expiresAtMs > reading.readAtMs,
                  reading.readAtMs / 1_000 <= date.timeIntervalSince1970 + 60,
                  usage.nextResetMs.map({ $0.isFinite && $0 > 0 }) ?? true else {
                previous = nil
                return empty(.unsupportedFormat)
            }
            let sample = Sample(
                account: account,
                used: usage.percentUsed,
                observedAt: Date(timeIntervalSince1970: reading.readAtMs / 1_000),
                expiresAt: Date(timeIntervalSince1970: cache.expiresAtMs / 1_000),
                resetsAt: usage.nextResetMs.map { Date(timeIntervalSince1970: $0 / 1_000) }
            )
            previous = sample
            return result(sample, at: date)
        } catch {
            // A half-written cache may keep a valid sample only for the same active account.
            let cacheURL = rootDirectory.appendingPathComponent(GrokCacheFile.fileName(for: GrokCacheFile.quotaKey(account: account)))
            guard activeAccount() == account,
                  FileManager.default.fileExists(atPath: cacheURL.path) else {
                previous = nil
                return empty(.failed(Self.refreshMessage))
            }
            if let previous, previous.isValid(at: date) {
                return result(previous, at: date, readFailed: true)
            }
            previous = nil
            return empty(.failed(Self.refreshMessage))
        }
    }

    private static var refreshMessage: String {
        L10n.text(
            "订阅额度缓存不可用，请打开 Grok Bot 的 Usage & Billing 后刷新",
            "Subscription cache unavailable. Open Usage & Billing in Grok Bot, then refresh."
        )
    }

    private func activeAccount() -> String? {
        guard let data = try? readSlice(GrokCacheFile.accountKey, limit: 4_096),
              let envelope = try? JSONDecoder().decode(Envelope<String?>.self, from: data),
              envelope.schemaVersion == 1,
              let account = envelope.value, account.hasPrefix("grok|"),
              account.utf8.count > 5, account.utf8.count <= 512,
              !account.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        return account
    }

    private func readSlice(_ key: String, limit: Int) throws -> Data {
        let name = GrokCacheFile.fileName(for: key)
        let data = try reader(rootDirectory.appendingPathComponent(name), limit)
        guard name.hasSuffix(".kblob") else { return data }
        guard let newline = data.firstIndex(of: 10),
              let storedKey = try? JSONDecoder().decode(String.self, from: data[..<newline]),
              storedKey == key else { throw CocoaError(.fileReadCorruptFile) }
        return Data(data[data.index(after: newline)...])
    }

    private func result(_ sample: Sample, at date: Date, readFailed: Bool = false) -> ProviderResult {
        let valid = sample.isValid(at: date)
        let stale = readFailed || !valid || date.timeIntervalSince(sample.observedAt) > 300
        let windows = valid ? [RateLimitWindow(
            kind: .long, label: L10n.text("本周", "Weekly"), usedPercentage: sample.used,
            resetsAt: sample.resetsAt, durationMinutes: 10_080
        )] : []
        return ProviderResult(snapshot: UsageSnapshot(
            provider: id, windows: windows, todayTokens: nil, estimatedCostUSD: nil,
            observedAt: sample.observedAt,
            availability: stale ? .stale(lastUpdated: sample.observedAt) : .ready(lastUpdated: sample.observedAt)
        ), dailyUsage: [])
    }

    private func empty(_ availability: ProviderAvailability) -> ProviderResult {
        ProviderResult(snapshot: .empty(id, availability: availability), dailyUsage: [])
    }

    private struct Envelope<Value: Decodable>: Decodable {
        let schemaVersion: Int
        let value: Value
    }
    private struct QuotaCache: Decodable {
        let kind: String
        let selectedTeamId: Int?
        let reading: Reading?
        let expiresAtMs: Double
    }
    private struct Reading: Decodable {
        let usage: Usage
        let readAtMs: Double
    }
    private struct Usage: Decodable {
        let percentUsed: Double
        let nextResetMs: Double?
        let hasNonZeroIncludedLimit: Bool
        let isTeamSeat: Bool?
        let readForTeamId: Int?
    }
    private struct Sample {
        let account: String
        let used: Double
        let observedAt: Date
        let expiresAt: Date
        let resetsAt: Date?
        func isValid(at date: Date) -> Bool {
            date < expiresAt && date.timeIntervalSince(observedAt) < 86_400
                && (resetsAt.map { $0 > date } ?? true)
        }
    }
}

enum GrokCacheFile {
    static let accountKey = "sand.client.slice.client-meta.account-slot"

    static func quotaKey(account: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        let encoded = account.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "sand.client.slice.account.\(encoded).weekly-usage.cache"
    }

    static func fileName(for key: String) -> String {
        let bytes = Data(key.utf8)
        let encoded = base32(bytes) + ".blob"
        return encoded.utf8.count <= 240 ? encoded : base32(Data(SHA256.hash(data: bytes))) + ".kblob"
    }

    private static func base32(_ data: Data) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567".utf8)
        var output: [UInt8] = []
        var buffer: UInt32 = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[Int((buffer >> bits) & 31)])
            }
        }
        if bits > 0 { output.append(alphabet[Int((buffer << (5 - bits)) & 31)]) }
        return String(decoding: output, as: UTF8.self)
    }

    static func read(_ url: URL, _ limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= limit else { throw CocoaError(.fileReadCorruptFile) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
}
