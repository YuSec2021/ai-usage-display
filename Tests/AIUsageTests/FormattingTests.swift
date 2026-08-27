import XCTest
@testable import AIUsage

final class FormattingTests: XCTestCase {
    func testCompactNumber() {
        XCTAssertEqual(UsageFormatting.compactNumber(999), "999")
        XCTAssertEqual(UsageFormatting.compactNumber(1_250), "1.2K")
        XCTAssertEqual(UsageFormatting.compactNumber(1_500_000), "1.5M")
    }

    func testResetDescription() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(UsageFormatting.resetDescription(now.addingTimeInterval(3_900), now: now), "1 小时 5 分后重置")
        XCTAssertEqual(UsageFormatting.resetDescription(now.addingTimeInterval(120), now: now), "2 分后重置")
        XCTAssertEqual(UsageFormatting.resetDescription(now.addingTimeInterval(-1), now: now), "重置时间待更新")
    }

    func testLongResetDescriptionUsesDateInsteadOfWeekday() {
        let previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
        UserDefaults.standard.set(
            AppLanguage.simplifiedChinese.rawValue,
            forKey: AppLanguage.storageKey
        )
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
            }
        }

        let now = Date(timeIntervalSince1970: 1_782_000_000)
        let description = UsageFormatting.resetDescription(
            now.addingTimeInterval(2 * 86_400),
            now: now
        )

        XCTAssertTrue(description.contains("月"))
        XCTAssertTrue(description.contains("日"))
        XCTAssertFalse(description.contains("星期"))
        XCTAssertFalse(description.contains("周"))
    }

    func testDayPrecisionDoesNotInventAnExactResetTime() {
        let previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
        UserDefaults.standard.set(
            AppLanguage.simplifiedChinese.rawValue,
            forKey: AppLanguage.storageKey
        )
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
            }
        }

        let now = Date(timeIntervalSince1970: 1_782_000_000)
        let description = UsageFormatting.resetDescription(
            now.addingTimeInterval(25 * 86_400),
            precision: .day,
            now: now
        )

        XCTAssertTrue(description.contains("月"))
        XCTAssertTrue(description.contains("日"))
        XCTAssertTrue(description.hasSuffix("刷新"))
        XCTAssertFalse(description.contains(":"))
    }

    func testCachedTokensAreAnInputSubset() {
        let usage = TokenUsage(input: 120, cachedInput: 80, output: 30, reasoningOutput: 0)
        XCTAssertEqual(usage.total, 150)
    }

    func testPercentageIsClamped() {
        XCTAssertEqual(RateLimitWindow(kind: .short, label: "Test", usedPercentage: 140, resetsAt: nil).usedPercentage, 100)
        XCTAssertEqual(RateLimitWindow(kind: .short, label: "Test", usedPercentage: -4, resetsAt: nil).usedPercentage, 0)
    }

    func testStaleProviderDataRemainsUsableButVisiblyStale() {
        let availability = ProviderAvailability.stale(lastUpdated: .distantPast)
        XCTAssertTrue(availability.hasUsableData)
        XCTAssertTrue(availability.isStale)
        XCTAssertFalse(availability.isReady)
    }

    func testProviderSelectionDefaultsToEveryProvider() {
        XCTAssertEqual(
            ProviderID.selectedProviders(from: ProviderID.defaultSelectionRawValue),
            Set(ProviderID.allCases)
        )
    }

    func testProviderSelectionSupportsSingleAndNone() {
        XCTAssertEqual(ProviderID.selectedProviders(from: "codex"), [.codex])
        XCTAssertTrue(ProviderID.selectedProviders(from: "").isEmpty)
        XCTAssertEqual(ProviderID.selectionRawValue(for: [.claudeCode]), "claudeCode")
    }

    func testProviderOrderIgnoresDuplicatesAndAppendsNewProviders() {
        XCTAssertEqual(
            ProviderID.orderedProviders(from: "claudeCode,codex,claudeCode,unknown"),
            [.claudeCode, .codex, .kimiCode, .miniMax]
        )
    }

    func testProviderOrderCanMoveKimiFirstAndRoundTrip() {
        let reordered = ProviderID.moving(
            .kimiCode,
            toPositionOf: .codex,
            in: ProviderID.allCases
        )

        XCTAssertEqual(reordered, [.kimiCode, .codex, .claudeCode, .miniMax])
        let encoded = ProviderID.orderRawValue(for: reordered)
        XCTAssertEqual(encoded, "kimiCode,codex,claudeCode,miniMax")
        XCTAssertEqual(ProviderID.orderedProviders(from: encoded), reordered)
    }

    func testMenuBarUsesOnlyFirstThreeSelectedProvidersInPriorityOrder() {
        let providers = ProviderID.menuBarProviders(
            orderRawValue: "miniMax,kimiCode,claudeCode,codex",
            selectedProviders: Set(ProviderID.allCases)
        )

        XCTAssertEqual(providers, [.miniMax, .kimiCode, .claudeCode])
    }

    func testMenuBarFillsThreeSlotsAfterFilteringUnselectedProviders() {
        let providers = ProviderID.menuBarProviders(
            orderRawValue: "miniMax,kimiCode,claudeCode,codex",
            selectedProviders: [.miniMax, .claudeCode, .codex]
        )

        XCTAssertEqual(providers, [.miniMax, .claudeCode, .codex])
    }
}
