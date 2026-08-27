import Foundation

enum MiniMaxAPIRegion: String, CaseIterable, Identifiable {
    case mainlandChina
    case global

    static let storageKey = "minimax.api.region"
    var id: Self { self }

    var title: String {
        switch self {
        case .mainlandChina: L10n.text("中国大陆", "Mainland China")
        case .global: L10n.text("海外", "Global")
        }
    }

    var modelsEndpoint: URL {
        switch self {
        case .mainlandChina: URL(string: "https://api.minimaxi.com/v1/models")!
        case .global: URL(string: "https://api.minimax.io/v1/models")!
        }
    }

    var consoleURL: URL {
        switch self {
        case .mainlandChina: URL(string: "https://platform.minimaxi.com/user-center/basic-information/interface-key")!
        case .global: URL(string: "https://platform.minimax.io/user-center/basic-information/interface-key")!
        }
    }
}

enum MiniMaxCredentialStore {
    private static let service = "com.yusec.aiusage.minimax"

    static var apiKey: String? {
        APIKeyCredentialStore.load(environmentVariable: "MINIMAX_API_KEY", service: service)
    }

    static var isConfigured: Bool { apiKey != nil }

    static func save(_ value: String) throws {
        try APIKeyCredentialStore.save(value, service: service)
    }

    static func remove() throws {
        try APIKeyCredentialStore.remove(service: service)
    }
}

enum MiniMaxAuthorizationStatus: Equatable, Sendable {
    case authorized(modelCount: Int)
    case rejected
    case unavailable
}

enum MiniMaxAuthorizationAPI {
    static func verify(
        apiKey: String? = MiniMaxCredentialStore.apiKey,
        region: MiniMaxAPIRegion
    ) async -> MiniMaxAuthorizationStatus {
        guard let apiKey, !apiKey.isEmpty else { return .rejected }

        var request = URLRequest(url: region.modelsEndpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            if http.statusCode == 401 || http.statusCode == 403 { return .rejected }
            guard (200..<300).contains(http.statusCode),
                  let modelCount = modelCount(from: data) else {
                return .unavailable
            }
            return .authorized(modelCount: modelCount)
        } catch {
            return .unavailable
        }
    }

    static func modelCount(from data: Data) -> Int? {
        (try? JSONDecoder().decode(MiniMaxModelsResponse.self, from: data))?.data.count
    }
}

private struct MiniMaxModelsResponse: Decodable {
    let data: [MiniMaxModel]
}

private struct MiniMaxModel: Decodable {
    let id: String
}
