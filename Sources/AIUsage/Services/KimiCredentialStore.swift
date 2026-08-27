import Foundation
import Security

enum KimiCredentialStore {
    private static let service = "com.yusec.aiusage.kimi-code"

    static var apiKey: String? {
        APIKeyCredentialStore.load(environmentVariable: "KIMI_API_KEY", service: service)
    }

    static var isConfigured: Bool { apiKey != nil }

    static func save(_ value: String) throws {
        try APIKeyCredentialStore.save(value, service: service)
    }

    static func remove() throws {
        try APIKeyCredentialStore.remove(service: service)
    }
}

enum APIKeyCredentialStore {
    private static let account = "api-key"

    static func load(environmentVariable: String, service: String) -> String? {
        if let configured = ProcessInfo.processInfo.environment[environmentVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return configured
        }

        var result: CFTypeRef?
        guard SecItemCopyMatching(
            query(service: service, returningData: true) as CFDictionary,
            &result
        ) == errSecSuccess,
        let data = result as? Data,
        let value = String(data: data, encoding: .utf8),
        !value.isEmpty else { return nil }
        return value
    }

    static func save(_ value: String, service: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw APIKeyCredentialError.emptyKey }
        let itemQuery = query(service: service)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = itemQuery
            item.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw APIKeyCredentialError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw APIKeyCredentialError.keychain(updateStatus)
        }
    }

    static func remove(service: String) throws {
        let status = SecItemDelete(query(service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyCredentialError.keychain(status)
        }
    }

    private static func query(service: String, returningData: Bool = false) -> [String: Any] {
        var value: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if returningData {
            value[kSecReturnData as String] = true
            value[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return value
    }
}

enum APIKeyCredentialError: LocalizedError {
    case emptyKey
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            L10n.text("API Key 不能为空。", "API Key cannot be empty.")
        case .keychain(let status):
            L10n.text(
                "无法访问 macOS 钥匙串（错误 \(status)）。",
                "Unable to access macOS Keychain (error \(status))."
            )
        }
    }
}
