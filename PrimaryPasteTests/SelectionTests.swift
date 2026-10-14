import AppKit
import XCTest

final class SelectionTests: PrimaryPasteTestCase {
    func testSelectionTimingDefaultsFeelHuman() {
        let preferences = makePreferences()

        XCTAssertEqual(preferences.selectionCaptureDebounceMilliseconds, 40)
        XCTAssertEqual(
            preferences.selectionIntentWindowMilliseconds, PreferencesStore.defaultSelectionIntentWindowMilliseconds)
        XCTAssertEqual(PreferencesStore.defaultSelectionIntentWindowMilliseconds, 6_000)
        XCTAssertEqual(PreferencesStore.selectionIntentWindowRange, 750...12_000)
    }

    func testSelectionTimingLoadsCurrentValuesWithinBounds() {
        let customSuiteName = "com.abel.primarypaste.tests.\(UUID().uuidString)"
        let customDefaults = UserDefaults(suiteName: customSuiteName)!
        customDefaults.removePersistentDomain(forName: customSuiteName)
        customDefaults.set(9_000, forKey: "selectionIntentWindowMilliseconds")
        let custom = PreferencesStore(defaults: customDefaults)
        XCTAssertEqual(custom.selectionIntentWindowMilliseconds, 9_000)
        customDefaults.removePersistentDomain(forName: customSuiteName)

        let outOfRangeSuiteName = "com.abel.primarypaste.tests.\(UUID().uuidString)"
        let outOfRangeDefaults = UserDefaults(suiteName: outOfRangeSuiteName)!
        outOfRangeDefaults.removePersistentDomain(forName: outOfRangeSuiteName)
        outOfRangeDefaults.set(99_000, forKey: "selectionIntentWindowMilliseconds")
        let clamped = PreferencesStore(defaults: outOfRangeDefaults)
        XCTAssertEqual(
            clamped.selectionIntentWindowMilliseconds, PreferencesStore.selectionIntentWindowRange.upperBound)
        outOfRangeDefaults.removePersistentDomain(forName: outOfRangeSuiteName)
    }

    func testSelectionIntentTrackerScopesCaptureToGestureAppAndEnabledGesture() {
        let start = Date(timeIntervalSince1970: 100)
        let obsidian = SelectionIntentScope(
            processIdentifier: 100,
            bundleIdentifier: "md.obsidian",
            appName: "Obsidian"
        )
        let browser = SelectionIntentScope(
            processIdentifier: 200,
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        )
        var tracker = SelectionIntentTracker()

        tracker.noteSelectionGesture(.drag, scope: browser, now: start)
        let noExtraGestures = ManualSelectionGestures()

        XCTAssertTrue(
            tracker.allowsCapture(
                mode: .dragSelectionsOnly,
                manualGestures: noExtraGestures,
                currentScope: browser,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(1)
            )
        )
        XCTAssertFalse(
            tracker.allowsCapture(
                mode: .dragSelectionsOnly,
                manualGestures: noExtraGestures,
                currentScope: obsidian,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(1)
            )
        )
        XCTAssertFalse(
            tracker.allowsCapture(
                mode: .dragSelectionsOnly,
                manualGestures: noExtraGestures,
                currentScope: browser,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(7)
            )
        )

        tracker.noteSelectionGesture(.shiftArrow, scope: obsidian, now: start.addingTimeInterval(2))

        XCTAssertTrue(
            tracker.allowsCapture(
                mode: .customManualGestures,
                manualGestures: ManualSelectionGestures(shiftArrow: true),
                currentScope: obsidian,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(2.2)
            )
        )
        XCTAssertFalse(
            tracker.allowsCapture(
                mode: .customManualGestures,
                manualGestures: noExtraGestures,
                currentScope: obsidian,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(2.2)
            )
        )
        XCTAssertFalse(
            tracker.allowsCapture(
                mode: .customManualGestures,
                manualGestures: ManualSelectionGestures(shiftArrow: true),
                currentScope: obsidian,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(2.5)
            )
        )
        XCTAssertTrue(
            tracker.allowsCapture(
                mode: .anySelection,
                manualGestures: noExtraGestures,
                currentScope: obsidian,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(20)
            )
        )
    }

    func testSelectionIntentTrackerUsesShortPostDragSettleWindow() {
        let start = Date(timeIntervalSince1970: 150)
        let browser = SelectionIntentScope(
            processIdentifier: 200,
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        )
        var tracker = SelectionIntentTracker()

        tracker.noteSelectionGesture(.drag, scope: browser, now: start)
        XCTAssertTrue(
            tracker.allowsCapture(
                mode: .dragSelectionsOnly,
                manualGestures: ManualSelectionGestures(),
                currentScope: browser,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(5)
            )
        )

        tracker.endMouseDragSelectionGesture(scope: browser, now: start.addingTimeInterval(5))
        XCTAssertTrue(
            tracker.allowsCapture(
                mode: .dragSelectionsOnly,
                manualGestures: ManualSelectionGestures(),
                currentScope: browser,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(5.2)
            )
        )
        XCTAssertFalse(
            tracker.allowsCapture(
                mode: .dragSelectionsOnly,
                manualGestures: ManualSelectionGestures(),
                currentScope: browser,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(5.4)
            )
        )
    }

    func testSelectionIntentTrackerCanCancelStaleActiveDrag() {
        let start = Date(timeIntervalSince1970: 175)
        let browser = SelectionIntentScope(
            processIdentifier: 200,
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        )
        var tracker = SelectionIntentTracker()

        tracker.noteSelectionGesture(.drag, scope: browser, now: start)
        XCTAssertTrue(
            tracker.allowsCapture(
                mode: .dragSelectionsOnly,
                manualGestures: ManualSelectionGestures(),
                currentScope: browser,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(1)
            )
        )

        tracker.cancelMouseDragSelectionGesture()
        XCTAssertFalse(
            tracker.allowsCapture(
                mode: .dragSelectionsOnly,
                manualGestures: ManualSelectionGestures(),
                currentScope: browser,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(1.1)
            )
        )
    }

    func testSelectionIntentTrackerKeepsDoubleAndTripleClickSeparate() {
        let start = Date(timeIntervalSince1970: 200)
        let scope = SelectionIntentScope(
            processIdentifier: 300,
            bundleIdentifier: "com.example.editor",
            appName: "Editor"
        )
        var tracker = SelectionIntentTracker()

        tracker.noteSelectionGesture(.doubleClick, scope: scope, now: start)
        XCTAssertTrue(
            tracker.allowsCapture(
                mode: .customManualGestures,
                manualGestures: ManualSelectionGestures(doubleClick: true),
                currentScope: scope,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(0.2)
            )
        )

        tracker.noteSelectionGesture(.tripleClick, scope: scope, now: start.addingTimeInterval(2))
        XCTAssertFalse(
            tracker.allowsCapture(
                mode: .customManualGestures,
                manualGestures: ManualSelectionGestures(doubleClick: true),
                currentScope: scope,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(2.2)
            )
        )
        XCTAssertTrue(
            tracker.allowsCapture(
                mode: .customManualGestures,
                manualGestures: ManualSelectionGestures(tripleClick: true),
                currentScope: scope,
                activeDragWindow: 6,
                settleWindow: 0.3,
                now: start.addingTimeInterval(2.2)
            )
        )
    }

    func testEditableClassifierRejectsBrowserStaticText() {
        XCTAssertFalse(
            AccessibilityHelpers.isEditableTextElement(
                role: kAXStaticTextRole as String,
                subrole: "",
                isEditable: false,
                isValueSettable: false,
                isSelectedRangeSettable: false
            )
        )
        XCTAssertTrue(
            AccessibilityHelpers.isEditableTextElement(
                role: kAXTextFieldRole as String,
                subrole: "",
                isEditable: false,
                isValueSettable: false,
                isSelectedRangeSettable: false
            )
        )
        XCTAssertTrue(
            AccessibilityHelpers.isEditableTextElement(
                role: "AXGroup",
                subrole: "AXTextEntryArea",
                isEditable: false,
                isValueSettable: true,
                isSelectedRangeSettable: false
            )
        )
        XCTAssertFalse(
            AccessibilityHelpers.isEditableTextElement(
                role: "AXStaticText",
                subrole: "AXStaticText",
                isEditable: false,
                isValueSettable: false,
                isSelectedRangeSettable: true
            )
        )
    }

    func testSelectionStorePreservesExactTextTrimsPreviewsDeduplicatesAndCapsQueue() {
        let preferences = makePreferences()
        preferences.queueSize = 2
        let store = PrimarySelectionStore(preferences: preferences)

        store.record("  first item  ", sourceAppName: "Test", sourceBundleIdentifier: "test.app")
        store.record("first item", sourceAppName: "Test", sourceBundleIdentifier: "test.app")
        store.record("second\nitem", sourceAppName: "Test", sourceBundleIdentifier: "test.app")
        store.record("third item", sourceAppName: "Test", sourceBundleIdentifier: "test.app")

        XCTAssertEqual(store.queue.map(\.preview), ["second item", "third item"])
        XCTAssertEqual(store.current?.preview, "third item")

        let exactStore = PrimarySelectionStore(preferences: preferences)
        exactStore.record("    indented code\n", sourceAppName: "Test", sourceBundleIdentifier: "test.app")
        if case .text(let text) = exactStore.current?.payload {
            XCTAssertEqual(text, "    indented code\n")
        } else {
            XCTFail("Expected text payload")
        }
    }

    func testSelectionStoreQueueStackLatestAndCycleModes() {
        let preferences = makePreferences()
        preferences.queueSize = 5
        let store = PrimarySelectionStore(preferences: preferences)

        store.record("one", sourceAppName: "Test", sourceBundleIdentifier: nil)
        store.record("two", sourceAppName: "Test", sourceBundleIdentifier: nil)
        store.record("three", sourceAppName: "Test", sourceBundleIdentifier: nil)

        preferences.pasteMode = .latest
        XCTAssertEqual(store.consumeItem()?.preview, "three")

        preferences.pasteMode = .queue
        XCTAssertEqual(store.consumeItem()?.preview, "one")

        preferences.pasteMode = .stack
        XCTAssertEqual(store.consumeItem()?.preview, "three")

        preferences.pasteMode = .cycle
        XCTAssertEqual(store.consumeItem()?.preview, "one")
        XCTAssertEqual(store.consumeItem()?.preview, "two")
        XCTAssertEqual(store.consumeItem()?.preview, "three")
        XCTAssertEqual(store.consumeItem()?.preview, "one")
    }

    func testSelectionStoreClearAfterPasteMutatesExpectedMode() {
        let preferences = makePreferences()
        preferences.clearAfterPaste = true
        preferences.pasteMode = .queue
        let store = PrimarySelectionStore(preferences: preferences)

        store.record("one", sourceAppName: "Test", sourceBundleIdentifier: nil)
        store.record("two", sourceAppName: "Test", sourceBundleIdentifier: nil)

        XCTAssertEqual(store.consumeItem()?.preview, "one")
        XCTAssertEqual(store.queue.map(\.preview), ["two"])
        XCTAssertEqual(store.current?.preview, "two")

        preferences.pasteMode = .latest
        XCTAssertEqual(store.consumeItem()?.preview, "two")
        XCTAssertNil(store.current)
        XCTAssertTrue(store.queue.isEmpty)
    }

    func testOneLinePreviewCollapsesWhitespaceAndTruncates() {
        XCTAssertEqual("  alpha\n\n beta\tgamma ".oneLinePreview(), "alpha beta gamma")
        XCTAssertEqual("abcdefghijk".oneLinePreview(limit: 10), "abcdefghij...")
    }
    func testDifferentImagesWithIdenticalPreviewsAreRetained() {
        let store = PrimarySelectionStore(preferences: makePreferences())
        for bytes in [[UInt8(1), 2, 3], [UInt8(4), 5, 6]] {
            let item = NSPasteboardItem()
            item.setData(Data(bytes), forType: .png)
            store.record(
                PasteboardSnapshot(items: [item]), sourceAppName: "Images", sourceBundleIdentifier: "test.images")
        }
        XCTAssertEqual(store.queue.count, 2)
        XCTAssertEqual(store.queue[0].preview, store.queue[1].preview)
        if case .pasteboard(let snapshot) = store.current?.payload {
            XCTAssertEqual(snapshot.items.first?.data(forType: .png), Data([4, 5, 6]))
        } else {
            XCTFail("Expected the second image")
        }
    }

    func testSameFilenameInDifferentDirectoriesIsDifferentPayload() {
        let store = PrimarySelectionStore(preferences: makePreferences())
        for path in ["/tmp/one/same.txt", "/tmp/two/same.txt"] {
            store.record(
                PasteboardSnapshot(items: [], fileURLs: [URL(fileURLWithPath: path)]), sourceAppName: "Finder",
                sourceBundleIdentifier: "com.apple.finder")
        }
        XCTAssertEqual(store.queue.count, 2)
    }

    func testIdenticalPayloadIsDeduplicatedButSourceChangesAreRecorded() {
        let store = PrimarySelectionStore(preferences: makePreferences())
        let item = NSPasteboardItem()
        item.setData(Data([1, 2, 3]), forType: .png)
        let snapshot = PasteboardSnapshot(items: [item])
        store.record(snapshot, sourceAppName: "First", sourceBundleIdentifier: "test.first")
        store.record(snapshot, sourceAppName: "First", sourceBundleIdentifier: "test.first")
        XCTAssertEqual(store.queue.count, 1)
        store.record(snapshot, sourceAppName: "Second", sourceBundleIdentifier: "test.second")
        XCTAssertEqual(store.queue.count, 2)
        XCTAssertEqual(store.current?.sourceAppName, "Second")
    }

    func testPeekDoesNotConsumeAndSuccessfulPasteCommitsOriginalMode() throws {
        let preferences = makePreferences()
        preferences.pasteMode = .queue
        preferences.clearAfterPaste = true
        let store = PrimarySelectionStore(preferences: preferences)
        store.record("one", sourceAppName: "Test", sourceBundleIdentifier: nil)
        store.record("two", sourceAppName: "Test", sourceBundleIdentifier: nil)
        let next = try XCTUnwrap(store.peekItem())
        XCTAssertEqual(next.preview, "one")
        XCTAssertEqual(store.queue.count, 2)
        preferences.pasteMode = .latest
        store.didPaste(next, mode: .queue, clearAfterPaste: true)
        XCTAssertEqual(store.queue.map(\.preview), ["two"])
        XCTAssertEqual(store.current?.preview, "two")
    }

    func testLoweringRetentionLimitImmediatelyPrunesQueueAndKeepsCycleValid() {
        let preferences = makePreferences()
        preferences.pasteMode = .cycle
        let store = PrimarySelectionStore(preferences: preferences)
        for value in ["one", "two", "three", "four"] {
            store.record(value, sourceAppName: "Test", sourceBundleIdentifier: nil)
        }
        _ = store.consumeItem()
        _ = store.consumeItem()
        _ = store.consumeItem()
        preferences.queueSize = 2
        XCTAssertEqual(store.queue.map(\.preview), ["three", "four"])
        XCTAssertEqual(store.peekItem()?.preview, "four")
        preferences.queueSize = -100
        XCTAssertEqual(store.queue.count, 1)
        XCTAssertEqual(store.consumeItem()?.preview, "four")
    }

    func testAccessibilityTextRangesRejectOverflowAndInvalidOffsets() {
        XCTAssertTrue(AccessibilityHelpers.isValidTextRange(NSRange(location: 1, length: 2), utf16Length: 4))
        XCTAssertTrue(AccessibilityHelpers.isValidTextRange(NSRange(location: 4, length: 0), utf16Length: 4))
        for range in [
            NSRange(location: NSNotFound, length: 1), NSRange(location: -1, length: 1),
            NSRange(location: 1, length: -1), NSRange(location: Int.max - 1, length: Int.max),
            NSRange(location: 2, length: 3),
        ] {
            XCTAssertFalse(AccessibilityHelpers.isValidTextRange(range, utf16Length: 4))
        }
    }

}
