import AppKit
import XCTest

final class PreferencesTests: PrimaryPasteTestCase {
    func testPreferenceCapNormalization() {
        XCTAssertEqual(PreferencesStore.normalizedMaximumSelectionLength(-1), 0)
        XCTAssertEqual(PreferencesStore.normalizedMaximumSelectionLength(0), 0)
        XCTAssertEqual(PreferencesStore.normalizedMaximumSelectionLength(1), 500)
        XCTAssertEqual(PreferencesStore.normalizedMaximumSelectionLength(500), 500)
        XCTAssertEqual(PreferencesStore.normalizedMaximumSelectionLength(250_001), 250_000)

        XCTAssertEqual(PreferencesStore.normalizedMaximumFileSelectionCount(0), 1)
        XCTAssertEqual(PreferencesStore.normalizedMaximumFileSelectionCount(1), 1)
        XCTAssertEqual(PreferencesStore.normalizedMaximumFileSelectionCount(501), 500)

        XCTAssertEqual(PreferencesStore.normalizedCaptureToastDisplaySeconds(0.3), 1.0)
        XCTAssertEqual(PreferencesStore.normalizedCaptureToastDisplaySeconds(2.6), 2.6)
        XCTAssertEqual(PreferencesStore.normalizedCaptureToastDisplaySeconds(8.0), 4.0)
    }

    func testExtraWindowsAndSupportAreOptInWhileSavedChoicesArePreserved() {
        let suiteName = "com.abel.primarypaste.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(defaults: defaults)

        XCTAssertFalse(preferences.showSetupOnLaunch)
        preferences.showSetupOnLaunch = true
        XCTAssertTrue(PreferencesStore(defaults: defaults).showSetupOnLaunch)
        XCTAssertFalse(preferences.showSupport)
        preferences.showSupport = true
        XCTAssertTrue(preferences.showSupport)
        preferences.resetToDefaults()
        XCTAssertFalse(preferences.showSetupOnLaunch)
        XCTAssertFalse(preferences.showSupport)
    }

    func testCaptureToastSizeDefaultAndReset() {
        let preferences = makePreferences()

        XCTAssertEqual(preferences.captureToastSize, PreferencesStore.defaultCaptureToastSize)
        XCTAssertEqual(preferences.captureToastSize, .medium)
        XCTAssertEqual(preferences.captureToastDisplaySeconds, PreferencesStore.defaultCaptureToastDisplaySeconds)

        preferences.captureToastSize = .tiny
        XCTAssertEqual(preferences.captureToastSize, .tiny)
        preferences.captureToastDisplaySeconds = 3.4
        XCTAssertEqual(preferences.captureToastDisplaySeconds, 3.4)

        preferences.captureToastDisplaySeconds = 9.0
        XCTAssertEqual(preferences.captureToastDisplaySeconds, 4.0)

        preferences.resetToDefaults()
        XCTAssertEqual(preferences.captureToastSize, .medium)
        XCTAssertEqual(preferences.captureToastDisplaySeconds, PreferencesStore.defaultCaptureToastDisplaySeconds)
    }

    func testIconPreferencesDefaultAndReset() {
        let preferences = makePreferences()

        XCTAssertEqual(preferences.menuBarIconVariant, .defaultMenuBar)
        XCTAssertEqual(preferences.appIconVariant, .defaultAppIcon)
        XCTAssertTrue(preferences.showMenuBarStatusText)

        preferences.menuBarIconVariant = .dualLane
        preferences.appIconVariant = .mintSendTile
        preferences.showMenuBarStatusText = false

        preferences.resetToDefaults()

        XCTAssertEqual(preferences.menuBarIconVariant, .defaultMenuBar)
        XCTAssertEqual(preferences.appIconVariant, .defaultAppIcon)
        XCTAssertTrue(preferences.showMenuBarStatusText)
    }

    func testDerivedPermissionNeedsFollowEnabledPrivateAndModeSettings() {
        let preferences = makePreferences()

        XCTAssertTrue(preferences.shouldRunTextSelectionCapture)
        XCTAssertTrue(preferences.shouldMonitorMouseSelectionGestures)
        XCTAssertTrue(preferences.shouldMonitorMiddleClickEvents)
        XCTAssertTrue(preferences.shouldMonitorGlobalEvents)
        XCTAssertTrue(preferences.shouldUseAccessibility)

        preferences.isPrivateModeEnabled = true
        XCTAssertFalse(preferences.shouldRunTextSelectionCapture)
        XCTAssertFalse(preferences.shouldMonitorMouseSelectionGestures)
        XCTAssertTrue(preferences.shouldMonitorMiddleClickEvents)
        XCTAssertTrue(preferences.shouldUseAccessibility)

        preferences.isPrivateModeEnabled = false
        preferences.selectionCaptureMode = .anySelection
        XCTAssertFalse(preferences.shouldMonitorMouseSelectionGestures)
        XCTAssertFalse(preferences.shouldMonitorKeyboardSelectionGestures)
        XCTAssertTrue(preferences.shouldMonitorMiddleClickEvents)

        preferences.selectionCaptureMode = .customManualGestures
        XCTAssertTrue(preferences.shouldMonitorMouseSelectionGestures)
        XCTAssertFalse(preferences.shouldMonitorKeyboardSelectionGestures)
        preferences.captureShiftArrowSelections = true
        XCTAssertTrue(preferences.shouldMonitorKeyboardSelectionGestures)
    }
    func testInvalidSavedNumbersCannotCrashCaptureOrRetention() {
        let suiteName = "com.abel.primarypaste.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(-100, forKey: "queueSize")
        defaults.set(Int.max, forKey: "selectionCaptureDebounceMilliseconds")
        defaults.set(-500, forKey: "minimumSelectionLength")
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertEqual(preferences.queueSize, 1)
        XCTAssertEqual(preferences.selectionCaptureDebounceMilliseconds, 900)
        XCTAssertEqual(preferences.minimumSelectionLength, 1)
        preferences.queueSize = Int.max
        preferences.selectionCaptureDebounceMilliseconds = Int.min
        preferences.selectionIntentWindowMilliseconds = Int.min
        preferences.captureToastDisplaySeconds = .nan
        XCTAssertEqual(preferences.queueSize, 50)
        XCTAssertEqual(preferences.selectionCaptureDebounceMilliseconds, 0)
        XCTAssertEqual(preferences.selectionIntentWindowMilliseconds, 750)
        XCTAssertEqual(preferences.captureToastDisplaySeconds, PreferencesStore.defaultCaptureToastDisplaySeconds)
        XCTAssertEqual(PreferencesStore(defaults: defaults).queueSize, 50)
    }

}
