import Foundation

enum UsageFormatting {
    static func compactNumber(_ value: Int) -> String {
        let number = Double(value)
        if number >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        }
        if number >= 1_000 {
            return String(format: "%.1fK", number / 1_000)
        }
        return String(value)
    }

    static func resetDescription(
        _ date: Date?,
        precision: ResetTimePrecision = .exact,
        now: Date = Date()
    ) -> String {
        guard let date else { return L10n.text("重置时间未知", "Reset time unknown") }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else {
            return L10n.text("重置时间待更新", "Reset time pending")
        }

        if precision == .day {
            let formatter = DateFormatter()
            formatter.locale = AppLanguage.current.locale
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
            return L10n.text(
                "\(formatter.string(from: date))刷新",
                "Refreshes \(formatter.string(from: date))"
            )
        }

        if seconds < 86_400 {
            let hours = Int(seconds) / 3_600
            let minutes = (Int(seconds) % 3_600) / 60
            if hours > 0 {
                return L10n.text("\(hours) 小时 \(minutes) 分后重置", "Resets in \(hours)h \(minutes)m")
            }
            return L10n.text("\(max(minutes, 1)) 分后重置", "Resets in \(max(minutes, 1))m")
        }

        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM d HH:mm")
        return L10n.text("\(formatter.string(from: date))重置", "Resets \(formatter.string(from: date))")
    }

    static func updatedDescription(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 10 { return L10n.text("刚刚更新", "Updated just now") }
        if seconds < 60 { return L10n.text("\(Int(seconds)) 秒前更新", "Updated \(Int(seconds))s ago") }
        if seconds < 3_600 { return L10n.text("\(Int(seconds / 60)) 分前更新", "Updated \(Int(seconds / 60))m ago") }
        return L10n.text("\(Int(seconds / 3_600)) 小时前更新", "Updated \(Int(seconds / 3_600))h ago")
    }
}
