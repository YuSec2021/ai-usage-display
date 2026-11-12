import XCTest
import SwiftUI
import AppKit
@testable import AIUsage

final class PresentationTests: XCTestCase {
    private func snapshot(
        _ provider: ProviderID = .codex,
        fiveHour: Double? = 37,
        weekly: Double = 91
    ) -> UsageSnapshot {
        let now = Date()
        var windows = [RateLimitWindow(
            kind: .long, label: "7 天", usedPercentage: weekly,
            resetsAt: now.addingTimeInterval(86_400), durationMinutes: 10_080
        )]
        if let fiveHour {
            windows.append(RateLimitWindow(
                kind: .short, label: "5 小时", usedPercentage: fiveHour,
                resetsAt: now.addingTimeInterval(3_600), durationMinutes: 300
            ))
        }
        return UsageSnapshot(
            provider: provider, windows: windows,
            todayTokens: TokenUsage(input: 120_000, cachedInput: 90_000, output: 8_000, reasoningOutput: 0),
            estimatedCostUSD: nil, observedAt: now, availability: .ready(lastUpdated: now)
        )
    }

    func testRingSelectsFiveHourWindowEvenWhenWeeklyWindowComesFirst() {
        XCTAssertEqual(snapshot().fiveHourWindow()?.usedPercentage, 37)
        XCTAssertNil(snapshot(fiveHour: nil).fiveHourWindow())
        var otherDuration = snapshot()
        otherDuration.windows = [RateLimitWindow(
            kind: .short, label: "2 hours", usedPercentage: 50, resetsAt: nil, durationMinutes: 120
        )]
        XCTAssertNil(otherDuration.fiveHourWindow())
    }

    func testExpiredOrUnavailableQuotaDoesNotBecomeCurrentRing() {
        var value = snapshot()
        let reset = value.fiveHourWindow()!.resetsAt!
        XCTAssertNil(value.fiveHourWindow(at: reset))
        value.availability = .unsupportedFormat
        XCTAssertNil(value.fiveHourWindow())
    }

    func testHighestModeComparesFiveHourUsageAndPreservesProviderIdentity() {
        let codex = snapshot(.codex, fiveHour: 60, weekly: 10)
        let claude = snapshot(.claudeCode, fiveHour: 20, weekly: 99)
        let weeklyOnly = snapshot(.kimiCode, fiveHour: nil, weekly: 100)
        let snapshots = [codex, claude, weeklyOnly]
        XCTAssertEqual(MenuBarDisplayMode.highestUsage.displayedSnapshots(from: snapshots).map(\.provider), [.codex])
        XCTAssertEqual(MenuBarDisplayMode.bothProviders.displayedSnapshots(from: snapshots), snapshots)
        XCTAssertEqual(MenuBarDisplayMode.iconOnly.displayedSnapshots(from: snapshots).map(\.provider), [.codex])
        XCTAssertEqual(MenuBarDisplayMode.highestUsage.displayedSnapshots(from: [weeklyOnly]).first?.provider, .kimiCode)
        XCTAssertTrue(MenuBarDisplayMode.highestUsage.displayedSnapshots(from: []).isEmpty)
    }

    func testExpiredFiveHourStatusExplainsResetWithoutInventingCurrentUsage() {
        let value = snapshot()
        let reset = value.fiveHourWindow()!.resetsAt!
        XCTAssertNil(value.fiveHourWindow(at: reset))
        XCTAssertEqual(value.fiveHourStatusDescription(at: reset), "上个周期已结束，等待 Codex 更新额度")
        XCTAssertEqual(snapshot(fiveHour: nil).fiveHourStatusDescription(), "暂无 5 小时额度数据")
        let newWindow = snapshot(fiveHour: 0)
        XCTAssertEqual(newWindow.fiveHourWindow()?.usedPercentage, 0)
        XCTAssertNotEqual(newWindow.fiveHourStatusDescription(), value.fiveHourStatusDescription(at: reset))
    }

    func testTransparencyBoundsAndAccessibilityOverride() {
        XCTAssertEqual(GlassAppearance.backgroundOpacity(transparency: 0, reduceTransparency: false), 1)
        XCTAssertEqual(GlassAppearance.backgroundOpacity(transparency: 1, reduceTransparency: false), 0)
        XCTAssertEqual(GlassAppearance.backgroundOpacity(transparency: 0.7, reduceTransparency: false), 0.3, accuracy: 0.001)
        XCTAssertEqual(GlassAppearance.backgroundOpacity(transparency: -2, reduceTransparency: false), 1)
        XCTAssertEqual(GlassAppearance.backgroundOpacity(transparency: 2, reduceTransparency: false), 0)
        XCTAssertEqual(GlassAppearance.backgroundOpacity(transparency: .nan, reduceTransparency: false), 0.45, accuracy: 0.001)
        XCTAssertEqual(GlassAppearance.backgroundOpacity(transparency: 1, reduceTransparency: true), 1)
    }

    @MainActor
    func testMenuBarImagesDistinguishUnknownZeroPartialAndFullUsage() async throws {
        let images = try [nil, 0.0, 50.0, 100.0].map { usage in
            try XCTUnwrap(MenuBarRingImage.make(snapshots: [snapshot(fiveHour: usage)]))
        }
        for image in images {
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 22, height: 22))
        }
        let representations = try images.map { try XCTUnwrap($0.tiffRepresentation) }
        XCTAssertEqual(Set(representations).count, 4)
        XCTAssertNil(MenuBarRingImage.make(snapshots: []))
        let threeModels = try XCTUnwrap(MenuBarRingImage.make(snapshots: [snapshot(), snapshot(.claudeCode), snapshot(.kimiCode)]))
        XCTAssertEqual(threeModels.size.width, 76)
    }

    @MainActor
    func testRenderCardAndRingPreviewsWithIsolatedFixtures() async throws {
        guard ProcessInfo.processInfo.environment["AI_USAGE_RENDER_PREVIEWS"] == "1" else {
            throw XCTSkip("Preview export requires a local GPU; enable AI_USAGE_RENDER_PREVIEWS to render artifacts.")
        }
        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/ui-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let content = VStack(spacing: 14) {
                HStack {
                    Text("AI Usage").font(.title3.weight(.semibold))
                    Spacer()
                    Text("示例数据").font(.caption).foregroundStyle(.secondary)
                }
                ProviderCard(snapshot: snapshot(), showsDragHandle: true)
                ProviderCard(snapshot: snapshot(.claudeCode, fiveHour: 82, weekly: 45), showsDragHandle: true)
                HStack(spacing: 20) {
                    ForEach([0.0, 50.0, 100.0], id: \.self) { usage in
                        UsageRing(provider: .codex, window: self.snapshot(fiveHour: usage).fiveHourWindow(), size: 38)
                    }
                    UsageRing(provider: .codex, window: nil, size: 38)
                }
            }
            .padding(18)
            .frame(width: 390)
            .environment(\.colorScheme, scheme)
            .background(scheme == .dark ? Color(red: 0.09, green: 0.105, blue: 0.13) : Color(red: 0.965, green: 0.975, blue: 0.99))
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let cgImage = try XCTUnwrap(renderer.cgImage)
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent("usage-rings-\(name).png"))
        }
    }
}
