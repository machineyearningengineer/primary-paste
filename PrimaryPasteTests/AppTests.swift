import AppKit
import XCTest

final class AppTests: PrimaryPasteTestCase {
    func testPracticeReopeningAfterCacheEvictionUsesFreshBrowserURL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try PracticePageCache.write(html: "Meet at 10:30. Clipboard stays separate.", in: directory)
        try FileManager.default.removeItem(at: first)
        let reopened = try PracticePageCache.write(html: "Meet at 10:30. Clipboard stays separate.", in: directory)
        XCTAssertNotEqual(first, reopened)
        let html = try String(contentsOf: reopened, encoding: .utf8)
        XCTAssertTrue(html.contains("Meet at 10:30."))
        XCTAssertTrue(html.contains("Clipboard stays separate."))
        XCTAssertFalse(html.contains("{{clipboard-detail}}"))
    }

    func testPracticeCacheIsBoundedAndPreservesUnrelatedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unrelated = directory.appendingPathComponent("first-paste-not-owned.html")
        try "Keep this".write(to: unrelated, atomically: true, encoding: .utf8)
        for _ in 0..<8 {
            _ = try PracticePageCache.write(html: "Separate", in: directory)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 6)
        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "Keep this")
    }

    func testSetupLaunchPolicyKeepsBackgroundLaunchesQuiet() {
        XCTAssertFalse(
            SetupLaunchPolicy.shouldOpenSetupWindowOnLaunch(
                showSetupOnLaunch: true,
                needsAccessibilitySetup: true,
                needsInputMonitoringSetup: true,
                needsFinderAutomationSetup: true,
                isAppActive: false
            )
        )
    }

    func testSetupLaunchPolicyOpensOnlyForActiveRequestedOrRequiredSetup() {
        XCTAssertTrue(
            SetupLaunchPolicy.shouldOpenSetupWindowOnLaunch(
                showSetupOnLaunch: true,
                needsAccessibilitySetup: false,
                needsInputMonitoringSetup: false,
                needsFinderAutomationSetup: false,
                isAppActive: true
            )
        )

        XCTAssertTrue(
            SetupLaunchPolicy.shouldOpenSetupWindowOnLaunch(
                showSetupOnLaunch: false,
                needsAccessibilitySetup: true,
                needsInputMonitoringSetup: false,
                needsFinderAutomationSetup: false,
                isAppActive: true
            )
        )

        XCTAssertFalse(
            SetupLaunchPolicy.shouldOpenSetupWindowOnLaunch(
                showSetupOnLaunch: false,
                needsAccessibilitySetup: false,
                needsInputMonitoringSetup: false,
                needsFinderAutomationSetup: false,
                isAppActive: true
            )
        )
    }
}
