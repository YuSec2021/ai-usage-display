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
    }

    func testPercentageIsClamped() {
        XCTAssertEqual(RateLimitWindow(kind: .short, label: "Test", usedPercentage: 140, resetsAt: nil).usedPercentage, 100)
        XCTAssertEqual(RateLimitWindow(kind: .short, label: "Test", usedPercentage: -4, resetsAt: nil).usedPercentage, 0)
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
}
