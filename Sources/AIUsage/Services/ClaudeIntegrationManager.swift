import Foundation

enum ClaudeIntegrationError: LocalizedError {
    case invalidSettings
    case unableToCreateFiles

    var errorDescription: String? {
        switch self {
        case .invalidSettings: L10n.text("Claude Code 设置文件不是有效的 JSON。", "The Claude Code settings file is not valid JSON.")
        case .unableToCreateFiles: L10n.text("无法创建 Claude Code 用量收集文件。", "Unable to create Claude Code usage collection files.")
        }
    }
}

enum ClaudeIntegrationManager {
    private static let marker = "ai-usage-claude-wrapper.sh"
    private static var settingsURL: URL {
        ProviderPaths.claudeDirectory.appendingPathComponent("settings.json")
    }
    private static var supportURL: URL { ProviderPaths.applicationSupport }
    private static var wrapperURL: URL { supportURL.appendingPathComponent(marker) }
    private static var collectorURL: URL { supportURL.appendingPathComponent("claude-snapshot-collector.js") }
    private static var originalCommandURL: URL { supportURL.appendingPathComponent("claude-original-statusline-command.txt") }
    private static var backupURL: URL { supportURL.appendingPathComponent("claude-statusline-backup.json") }

    static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = object["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else { return false }
        return command.contains(marker)
    }

    static func install() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: ProviderPaths.claudeDirectory, withIntermediateDirectories: true)

        var settings = try loadSettings()
        let current = settings["statusLine"]
        let currentDictionary = current as? [String: Any]

        if !isInstalled {
            let backup: [String: Any] = [
                "hadOriginal": current != nil,
                "statusLine": current ?? NSNull()
            ]
            try writeJSON(backup, to: backupURL)

            if let command = currentDictionary?["command"] as? String, !command.isEmpty {
                try command.write(to: originalCommandURL, atomically: true, encoding: .utf8)
            } else {
                try? fileManager.removeItem(at: originalCommandURL)
            }
        }

        try collectorScript.write(to: collectorURL, atomically: true, encoding: .utf8)
        try wrapperScript.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)

        var statusLine = currentDictionary ?? ["type": "command"]
        statusLine["type"] = "command"
        statusLine["command"] = shellQuote(wrapperURL.path)
        statusLine["refreshInterval"] = statusLine["refreshInterval"] ?? 5
        settings["statusLine"] = statusLine
        try writeJSON(settings, to: settingsURL)
    }

    static func uninstall() throws {
        var settings = try loadSettings()
        guard isInstalled else { return }

        if let data = try? Data(contentsOf: backupURL),
           let backup = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           backup["hadOriginal"] as? Bool == true,
           let original = backup["statusLine"], !(original is NSNull) {
            settings["statusLine"] = original
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try writeJSON(settings, to: settingsURL)

        for url in [wrapperURL, collectorURL, originalCommandURL, backupURL] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeIntegrationError.invalidSettings
        }
        return object
    }

    private static func writeJSON(_ object: Any, to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else { throw ClaudeIntegrationError.invalidSettings }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static var wrapperScript: String {
        let collector = shellQuote(collectorURL.path)
        let snapshot = shellQuote(supportURL.appendingPathComponent("claude-snapshot.json").path)
        let original = shellQuote(originalCommandURL.path)
        return """
        #!/bin/zsh
        input_file=$(/usr/bin/mktemp -t ai-usage-claude)
        trap '/bin/rm -f "$input_file"' EXIT
        /bin/cat > "$input_file"
        /usr/bin/osascript -l JavaScript \(collector) "$input_file" \(snapshot) >/dev/null 2>&1 || true
        if [ -s \(original) ]; then
          original_command=$(/bin/cat \(original))
          /bin/zsh -lc "$original_command" < "$input_file"
        fi
        """
    }

    private static let collectorScript = """
    ObjC.import('Foundation');

    function run(argv) {
      const inputPath = argv[0];
      const outputPath = argv[1];
      const sourceString = $.NSString.stringWithContentsOfFileEncodingError(
        inputPath, $.NSUTF8StringEncoding, null
      );
      if (!sourceString) return;
      const source = JSON.parse(ObjC.unwrap(sourceString));
      const snapshot = {
        collected_at: Date.now() / 1000,
        model: source.model || null,
        cost: source.cost || null,
        context_window: source.context_window || null,
        rate_limits: source.rate_limits || null,
        session_id: source.session_id || null,
        version: source.version || null
      };
      const output = $(JSON.stringify(snapshot));
      output.writeToFileAtomicallyEncodingError(
        outputPath, true, $.NSUTF8StringEncoding, null
      );
    }
    """
}
