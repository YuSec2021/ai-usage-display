import Foundation
import Combine

@MainActor
final class KimiConnectionModel: ObservableObject {
    enum State { case unconfigured, configured, verifying, connected, failed }
    @Published private(set) var state = State.unconfigured
    @Published private(set) var message: String?
    private var generation = 0
    private let readKey: () -> String?
    private let writeKey: (String) throws -> Void
    private let deleteKey: () throws -> Void
    private let loader: @Sendable (String) async -> KimiRateLimitSample?

    init(
        readKey: @escaping () -> String? = { KimiCredentialStore.apiKey },
        writeKey: @escaping (String) throws -> Void = KimiCredentialStore.save,
        deleteKey: @escaping () throws -> Void = KimiCredentialStore.remove,
        loader: @escaping @Sendable (String) async -> KimiRateLimitSample? = { await KimiUsageAPI.load(apiKey: $0) }
    ) {
        self.readKey = readKey
        self.writeKey = writeKey
        self.deleteKey = deleteKey
        self.loader = loader
    }

    var isConfigured: Bool { state != .unconfigured }
    var isVerified: Bool { state == .connected }
    var statusDescription: String {
        switch state {
        case .unconfigured:
            L10n.text("配置 API Key 后显示 5 小时与每周额度", "Add an API Key to show 5-hour and weekly limits")
        case .verifying:
            L10n.text("正在验证 API Key", "Verifying API Key")
        case .connected:
            L10n.text("5 小时与每周额度已连接", "5-hour and weekly limits connected")
        case .configured, .failed:
            L10n.text("API Key 已配置，等待验证", "API Key configured; awaiting verification")
        }
    }

    func synchronize() {
        generation += 1
        state = readKey() == nil ? .unconfigured : .configured
        message = nil
    }

    func save(_ key: String) -> Bool {
        do {
            try writeKey(key)
            generation += 1
            state = .configured
            message = L10n.text("API Key 已安全保存，正在验证。", "API Key saved securely. Verifying.")
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func remove() -> Bool {
        do {
            try deleteKey()
            generation += 1
            state = .unconfigured
            message = L10n.text("API Key 已从 macOS 钥匙串移除。", "API Key removed from macOS Keychain.")
            return true
        } catch { message = error.localizedDescription; return false }
    }

    @discardableResult
    func verify(showSuccessMessage: Bool = false) async -> Bool {
        guard let key = readKey() else { synchronize(); return false }
        generation += 1
        let request = generation
        state = .verifying
        message = nil
        let sample = await loader(key)
        guard request == generation else { return false }
        guard readKey() == key, !Task.isCancelled else { synchronize(); return false }
        state = sample == nil ? .failed : .connected
        if sample == nil {
            message = L10n.text("无法验证 API Key，请检查 Key 或网络后重试。", "Unable to verify the API Key. Check the key or network and try again.")
        } else if showSuccessMessage {
            message = L10n.text("连接成功，Kimi 额度已更新。", "Connected. Kimi limits updated.")
        }
        return true
    }
}
