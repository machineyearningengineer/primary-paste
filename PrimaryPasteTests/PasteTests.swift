import AppKit
import XCTest

final class PasteTests: PrimaryPasteTestCase {
    func testDeepWebEditorAndIncompleteAncestryUseNormalPaste() {
        let codexLike = EditableTargetSurface.classifyAncestors(
            startingAt: 0,
            parent: { $0 < 30 ? $0 + 1 : nil },
            isWebContent: { $0 == 22 }
        )
        XCTAssertFalse(codexLike.supportsDirectTextInsertion)

        let native = EditableTargetSurface.classifyAncestors(
            startingAt: 0,
            parent: { $0 < 6 ? $0 + 1 : nil },
            isWebContent: { _ in false }
        )
        XCTAssertTrue(native.supportsDirectTextInsertion)

        let incomplete = EditableTargetSurface.classifyAncestors(
            startingAt: 0, parent: { $0 + 1 }, isWebContent: { _ in false }
        )
        XCTAssertFalse(incomplete.supportsDirectTextInsertion)

        let cyclic = EditableTargetSurface.classifyAncestors(
            startingAt: 0, parent: { $0 }, isWebContent: { _ in false }
        )
        XCTAssertFalse(cyclic.supportsDirectTextInsertion)
    }

    func testModeTitlesStayUserReadableAndPasteTriggersDefaultOpinionated() {
        XCTAssertEqual(PasteMode.latest.title, "Latest")
        XCTAssertEqual(PasteMode.queue.title, "Queue")
        XCTAssertEqual(PasteMode.stack.title, "Stack")
        XCTAssertEqual(PasteMode.cycle.title, "Cycle")

        XCTAssertEqual(SelectionCaptureMode.dragSelectionsOnly.title, "Safe Drag")
        XCTAssertEqual(SelectionCaptureMode.customManualGestures.title, "Custom Gestures")
        XCTAssertEqual(SelectionCaptureMode.anySelection.title, "Everything")

        XCTAssertEqual(ClipboardLinkMode.separate.title, "Separate")
        XCTAssertEqual(ClipboardLinkMode.importCopies.title, "Import Copies")
        XCTAssertEqual(ClipboardLinkMode.mirrorSelections.title, "Mirror Selections")

        let preferences = PreferencesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertTrue(preferences.middleClickTriggerEnabled)
        XCTAssertFalse(preferences.keyboardShortcutTriggerEnabled)
        XCTAssertFalse(preferences.externalTriggerEnabled)
    }
}
