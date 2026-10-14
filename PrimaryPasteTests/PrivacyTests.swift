import AppKit
import XCTest

final class PrivacyTests: PrimaryPasteTestCase {
    func testPrivacyFilterAllowsOrdinaryText() {
        let preferences = makePreferences()
        let filter = PrivacyFilter(preferences: preferences)

        XCTAssertTrue(filter.allows("ordinary copied text"))
        XCTAssertTrue(filter.decision(for: "ordinary copied text").isAllowed)
    }

    func testPrivacyFilterDeniesPausedPrivateEmptyAndSensitiveText() {
        let preferences = makePreferences()
        let filter = PrivacyFilter(preferences: preferences)

        preferences.isEnabled = false
        assertDenied(filter.decision(for: "ordinary copied text")) { reason in
            if case .appDisabled = reason { return true }
            return false
        }

        preferences.isEnabled = true
        preferences.isPrivateModeEnabled = true
        assertDenied(filter.decision(for: "ordinary copied text")) { reason in
            if case .privateMode = reason { return true }
            return false
        }

        preferences.isPrivateModeEnabled = false
        assertDenied(filter.decision(for: "   \n\t  ")) { reason in
            if case .empty = reason { return true }
            return false
        }

        assertDenied(filter.decision(for: "api_key = abcdefghijklmnop123456")) { reason in
            if case .sensitive = reason { return true }
            return false
        }
    }

    func testPrivacyFilterLengthLimitsAreStructured() {
        let preferences = makePreferences()
        let filter = PrivacyFilter(preferences: preferences)

        preferences.minimumSelectionLength = 4
        assertDenied(filter.decision(for: "abc")) { reason in
            if case .tooShort(let minimum, let actual) = reason {
                return minimum == 4 && actual == 3
            }
            return false
        }
        assertDenied(filter.decision(for: "  abc  ")) { reason in
            if case .tooShort(let minimum, let actual) = reason {
                return minimum == 4 && actual == 3
            }
            return false
        }

        preferences.minimumSelectionLength = 1
        preferences.maximumSelectionLength = 500
        assertDenied(filter.decision(for: String(repeating: "x", count: 501))) { reason in
            if case .tooLong(let maximum, let actual) = reason {
                return maximum == 500 && actual == 501
            }
            return false
        }

        preferences.maximumSelectionLength = 0
        XCTAssertTrue(filter.allows(String(repeating: "x", count: 501)))
    }
}
