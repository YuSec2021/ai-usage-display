import Foundation

enum KimiUsageAPI {
    static let endpoint = URL(string: "https://api.kimi.com/coding/v1/usages")!

    static func load() async -> KimiRateLimitSample? {
        guard let apiKey = KimiCredentialStore.apiKey else { return nil }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            return decode(data, observedAt: Date())
        } catch {
            return nil
        }
    }

    static func decode(_ data: Data, observedAt: Date) -> KimiRateLimitSample? {
        guard let response = try? JSONDecoder().decode(KimiUsageResponse.self, from: data)
        else {
            return nil
        }

        let fiveHour = response.limits.first { limit in
            limit.window.duration == 300
                && limit.window.timeUnit.uppercased().contains("MINUTE")
        }?.detail
        guard response.usage != nil || fiveHour != nil else { return nil }

        return KimiRateLimitSample(
            fiveHour: fiveHour.flatMap(window(from:)),
            weekly: response.usage.flatMap(window(from:)),
            observedAt: observedAt
        )
    }

    private static func window(from detail: KimiUsageDetail) -> KimiRemoteWindow? {
        guard let limit = detail.limit, limit > 0 else { return nil }
        let used: Double
        if let explicitUsed = detail.used {
            used = explicitUsed
        } else if let remaining = detail.remaining {
            used = limit - remaining
        } else {
            return nil
        }

        return KimiRemoteWindow(
            usedPercentage: used / limit * 100,
            resetsAt: detail.resetTime.flatMap(parseDate)
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct KimiRateLimitSample: Sendable {
    let fiveHour: KimiRemoteWindow?
    let weekly: KimiRemoteWindow?
    let observedAt: Date
}

struct KimiRemoteWindow: Sendable {
    let usedPercentage: Double
    let resetsAt: Date?
}

private struct KimiUsageResponse: Decodable {
    let usage: KimiUsageDetail?
    let limits: [KimiUsageLimit]
}

private struct KimiUsageLimit: Decodable {
    let window: KimiUsageWindow
    let detail: KimiUsageDetail
}

private struct KimiUsageWindow: Decodable {
    let duration: Int
    let timeUnit: String
}

private struct KimiUsageDetail: Decodable {
    let limit: Double?
    let used: Double?
    let remaining: Double?
    let resetTime: String?

    private enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remaining
        case resetTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = container.flexibleDouble(forKey: .limit)
        used = container.flexibleDouble(forKey: .used)
        remaining = container.flexibleDouble(forKey: .remaining)
        resetTime = try container.decodeIfPresent(String.self, forKey: .resetTime)
    }
}

private extension KeyedDecodingContainer {
    func flexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}
