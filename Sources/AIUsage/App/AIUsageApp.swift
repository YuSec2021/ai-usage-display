import SwiftUI

@main
struct AIUsageApp: App {
    @StateObject private var store = UsageStore()
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.simplifiedChinese.rawValue

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Window(selectedLanguage == .english ? "Usage History" : "使用历史", id: "history") {
            HistoryView()
                .environmentObject(store)
        }
        .defaultSize(width: 800, height: 620)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
