import AppKit
import XCTest

final class SupportTests: PrimaryPasteTestCase {
    func testStructuredDiagnosticsAreBoundedAndContentFree() {
        let diagnostics = InteractionDiagnostics()
        for index in 0..<105 {
            diagnostics.recordPasteDecision("safe decision \(index)")
        }

        XCTAssertEqual(diagnostics.recentEvents.count, 100)
        XCTAssertTrue(diagnostics.recentEvents.allSatisfy { $0.capability == .paste })
        XCTAssertTrue(diagnostics.recentEvents.allSatisfy { $0.code == "paste-decision" })
    }

    func testTypedDiagnosticsRouteOnlySafeFieldsToSupport() {
        let diagnostics = InteractionDiagnostics()
        diagnostics.record(
            DiagnosticEvent(
                capability: .fileSelection,
                severity: .error,
                audience: .both,
                outcome: .failed,
                code: "finder-query-failed",
                supportMessage: "Finder query failed",
                metadata: .init(
                    itemCount: 3,
                    errorCategory: "AppleScriptError",
                    privateSystemDetail: "private system detail"
                )
            )
        )
        diagnostics.record(
            DiagnosticEvent(
                capability: .app,
                audience: .developers,
                code: "developer-only"
            )
        )

        XCTAssertEqual(diagnostics.recentEvents.count, 1)
        XCTAssertEqual(diagnostics.recentEvents.first?.supportMessage, "Finder query failed")
        XCTAssertEqual(diagnostics.recentEvents.first?.metadata.itemCount, 3)
        XCTAssertNil(diagnostics.recentEvents.first?.metadata.privateSystemDetail)
    }

    func testPassThroughEvidenceRequiresTargetSafetyDecision() {
        XCTAssertTrue(
            PastePassThroughEvidence.confirmsTargetSafety(
                "Passed through: pointer was not detected over an editable field"
            )
        )
        XCTAssertTrue(
            PastePassThroughEvidence.confirmsTargetSafety(
                "Passed through: target app keeps middle-click native"
            )
        )
        XCTAssertFalse(
            PastePassThroughEvidence.confirmsTargetSafety(
                "Compatibility paste skipped: Primary is empty"
            )
        )
        XCTAssertFalse(
            PastePassThroughEvidence.confirmsTargetSafety(
                "Passed through: app is paused"
            )
        )
    }

    func testPassThroughCoverageExcludesUnrelatedNoOps() {
        let diagnostics = InteractionDiagnostics()

        diagnostics.recordPastePassThrough(
            decision: "Compatibility paste skipped: Primary is empty",
            targetAppName: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )
        XCTAssertTrue(diagnostics.passThroughAppNames.isEmpty)

        diagnostics.recordPastePassThrough(
            decision: "Passed through: pointer was not detected over an editable field",
            targetAppName: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )
        XCTAssertEqual(diagnostics.passThroughAppNames, ["Safari"])
        XCTAssertEqual(diagnostics.passThroughBundleIdentifiers, ["com.apple.Safari"])
    }
}
