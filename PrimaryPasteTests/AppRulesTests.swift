import AppKit
import XCTest

final class AppRulesTests: PrimaryPasteTestCase {
    func testAppRulesManageBlockedAndPassThroughListsWithoutDuplicates() {
        let preferences = makePreferences()
        let rules = AppRulesEngine(
            preferences: preferences,
            selfBundleIdentifier: "com.abel.primarypaste"
        )

        rules.addBlockedBundleIdentifier("com.example.blocked")
        rules.addBlockedBundleIdentifier("com.example.blocked")
        XCTAssertEqual(preferences.blockedBundleIdentifiers.filter { $0 == "com.example.blocked" }.count, 1)

        rules.removeBlockedBundleIdentifier("com.example.blocked")
        XCTAssertFalse(preferences.blockedBundleIdentifiers.contains("com.example.blocked"))

        rules.addPassThroughBundleIdentifier("com.example.pass")
        rules.addPassThroughBundleIdentifier("com.example.pass")
        XCTAssertEqual(preferences.passThroughBundleIdentifiers, ["com.example.pass"])

        rules.removePassThroughBundleIdentifier("com.example.pass")
        XCTAssertTrue(preferences.passThroughBundleIdentifiers.isEmpty)
    }

    func testPassThroughAndCompatibilityRulesCannotConflict() {
        let preferences = makePreferences()
        let rules = AppRulesEngine(
            preferences: preferences,
            selfBundleIdentifier: "com.abel.primarypaste"
        )
        let target = AppRuleTarget(
            bundleIdentifier: "com.example.editor",
            displayName: "Example Editor"
        )

        rules.setCompatibilityMode(.compatibilityPasteAndCopySelection, for: target)
        XCTAssertNotNil(preferences.compatibilityRule(for: target.bundleIdentifier))

        rules.addPassThroughBundleIdentifier(target.bundleIdentifier)
        XCTAssertTrue(preferences.passThroughBundleIdentifiers.contains(target.bundleIdentifier))
        XCTAssertNil(preferences.compatibilityRule(for: target.bundleIdentifier))

        rules.setCompatibilityMode(.compatibilityPasteOnly, for: target)
        XCTAssertFalse(preferences.passThroughBundleIdentifiers.contains(target.bundleIdentifier))
        XCTAssertEqual(
            preferences.compatibilityRule(for: target.bundleIdentifier)?.integrationMode,
            .compatibilityPasteOnly
        )
    }

    func testAppRulesNormalizeBundleIdentifiers() {
        let preferences = makePreferences()
        let rules = AppRulesEngine(
            preferences: preferences,
            selfBundleIdentifier: "com.abel.primarypaste"
        )

        rules.addBlockedBundleIdentifier("  com.example.editor  ")
        rules.addBlockedBundleIdentifier("com.example.editor")
        rules.addPassThroughBundleIdentifier("  ")

        XCTAssertEqual(preferences.blockedBundleIdentifiers.filter { $0 == "com.example.editor" }.count, 1)
        XCTAssertFalse(preferences.blockedBundleIdentifiers.contains("  com.example.editor  "))
        XCTAssertTrue(preferences.passThroughBundleIdentifiers.isEmpty)
    }

    func testCompatibilityRulesPersistAndUpdateByBundleIdentifier() {
        let suiteName = "com.abel.primarypaste.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var preferences = PreferencesStore(defaults: defaults)
        preferences.setCompatibilityRule(
            AppCompatibilityRule(
                bundleIdentifier: "dev.example.editor",
                displayName: "Example Editor",
                integrationMode: .compatibilityPasteOnly
            )
        )
        preferences.setCompatibilityRule(
            AppCompatibilityRule(
                bundleIdentifier: "dev.example.editor",
                displayName: "Example Editor",
                integrationMode: .compatibilityPasteAndCopySelection,
                focusBeforePaste: false
            )
        )

        XCTAssertEqual(preferences.appCompatibilityRules.count, 1)
        XCTAssertEqual(
            preferences.compatibilityRule(for: "dev.example.editor")?.integrationMode,
            .compatibilityPasteAndCopySelection)
        XCTAssertEqual(preferences.compatibilityRule(for: "dev.example.editor")?.focusBeforePaste, false)

        preferences = PreferencesStore(defaults: defaults)
        XCTAssertEqual(preferences.appCompatibilityRules.count, 1)
        XCTAssertEqual(preferences.compatibilityRule(for: "dev.example.editor")?.displayName, "Example Editor")

        preferences.removeCompatibilityRule(bundleIdentifier: "dev.example.editor")
        XCTAssertTrue(preferences.appCompatibilityRules.isEmpty)
    }

    func testCompatibilityRulesNormalizeUntrustedPersistedValues() throws {
        let suiteName = "com.abel.primarypaste.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let rules = [
            AppCompatibilityRule(
                bundleIdentifier: " dev.example.editor ",
                displayName: " ",
                integrationMode: .compatibilityPasteOnly,
                copySelectionDelayMs: -50,
                minDragDistance: -4,
                minSelectionLength: -2,
                maxSelectionLength: 999_999
            ),
            AppCompatibilityRule(
                bundleIdentifier: "dev.example.editor",
                displayName: "Example Editor",
                integrationMode: .compatibilityPasteAndCopySelection,
                copySelectionDelayMs: 9_000,
                minDragDistance: 9_000,
                minSelectionLength: 400,
                maxSelectionLength: 20
            ),
            AppCompatibilityRule(
                bundleIdentifier: "dev.example.strict",
                displayName: "Strict App",
                integrationMode: .strictAXOnly
            ),
        ]
        defaults.set(try JSONEncoder().encode(rules), forKey: "appCompatibilityRules")

        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertEqual(preferences.appCompatibilityRules.count, 1)

        let rule = try XCTUnwrap(preferences.compatibilityRule(for: "dev.example.editor"))
        XCTAssertEqual(rule.displayName, "Example Editor")
        XCTAssertEqual(rule.integrationMode, .compatibilityPasteAndCopySelection)
        XCTAssertEqual(rule.copySelectionDelayMs, AppCompatibilityRule.copySelectionDelayRange.upperBound)
        XCTAssertEqual(rule.minDragDistance, AppCompatibilityRule.minDragDistanceRange.upperBound)
        XCTAssertEqual(rule.minSelectionLength, 400)
        XCTAssertEqual(rule.maxSelectionLength, 400)
        XCTAssertNil(preferences.compatibilityRule(for: "dev.example.strict"))
    }

    func testStrictCompatibilityModeRemovesExistingRule() {
        let preferences = makePreferences()
        preferences.setCompatibilityRule(
            AppCompatibilityRule(
                bundleIdentifier: "dev.example.editor",
                displayName: "Example Editor",
                integrationMode: .compatibilityPasteOnly
            )
        )

        preferences.setCompatibilityRule(
            AppCompatibilityRule(
                bundleIdentifier: "dev.example.editor",
                displayName: "Example Editor",
                integrationMode: .strictAXOnly
            )
        )

        XCTAssertTrue(preferences.appCompatibilityRules.isEmpty)
    }

    func testAppRulesIgnorePrimaryPasteItself() {
        let preferences = makePreferences()
        let rules = AppRulesEngine(
            preferences: preferences,
            selfBundleIdentifier: "com.abel.primarypaste"
        )

        rules.addBlockedBundleIdentifier("com.abel.primarypaste")
        rules.addPassThroughBundleIdentifier("com.abel.primarypaste")

        XCTAssertFalse(preferences.blockedBundleIdentifiers.contains("com.abel.primarypaste"))
        XCTAssertFalse(preferences.passThroughBundleIdentifiers.contains("com.abel.primarypaste"))
        XCTAssertTrue(rules.isSelfBundleIdentifier("com.abel.primarypaste"))
        XCTAssertFalse(rules.isSelfBundleIdentifier("com.example.other"))
    }
}
