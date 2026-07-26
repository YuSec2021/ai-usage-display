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

    static var kimiDirectory: URL {
        if let configured = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"],
           !configured.isEmpty {
            return URL(
                fileURLWithPath: (configured as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }

        let current = homeDirectory.appendingPathComponent(".kimi-code", isDirectory: true)
        if FileManager.default.fileExists(atPath: current.path) {
            return current
        }
        return homeDirectory.appendingPathComponent(".kimi", isDirectory: true)
    }

    static var miniMaxDesktopCacheDirectory: URL {
        homeDirectory
            .appendingPathComponent(
                "Library/Application Support/MiniMax/Cache/Cache_Data",
                isDirectory: true
            )
    }

    static var kimiDesktopLogURLs: [URL] {
        let directory = homeDirectory
            .appendingPathComponent("Library/Logs/kimi-desktop", isDirectory: true)
        return [
            directory.appendingPathComponent("main.old.log"),
            directory.appendingPathComponent("main.log")
        ]
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
