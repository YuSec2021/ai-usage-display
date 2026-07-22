import Foundation

protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func load() async -> ProviderResult
}

enum ProviderPaths {
    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var codexDirectory: URL {
        homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    static var claudeDirectory: URL {
        homeDirectory.appendingPathComponent(".claude", isDirectory: true)
    }

    static var claudeDesktopUsageHistory: URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
            .appendingPathComponent("plan-usage-history.json")
    }

    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AI Usage", isDirectory: true)
    }
}
