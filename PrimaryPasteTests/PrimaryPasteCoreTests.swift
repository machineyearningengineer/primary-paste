import AppKit
import XCTest

class PrimaryPasteTestCase: XCTestCase {
    func makePreferences(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> PreferencesStore {
        let suiteName = "com.abel.primarypaste.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated defaults", file: file, line: line)
            return PreferencesStore(defaults: .standard)
        }
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return PreferencesStore(defaults: defaults)
    }

    func assertDenied(
        _ decision: PrivacyFilterDecision,
        file: StaticString = #filePath,
        line: UInt = #line,
        reasonMatches: (PrivacyFilterDenialReason) -> Bool
    ) {
        switch decision {
        case .allowed:
            XCTFail("Expected privacy filter denial", file: file, line: line)
        case .denied(let reason):
            XCTAssertTrue(reasonMatches(reason), "Unexpected denial: \(reason)", file: file, line: line)
        }
    }
}
