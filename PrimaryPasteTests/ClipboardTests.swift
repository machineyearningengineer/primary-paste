import AppKit
import XCTest

final class ClipboardTests: PrimaryPasteTestCase {
    func testClipboardLinkModeDefinesCurrentBehavior() {
        let preferences = makePreferences()

        preferences.clipboardLinkMode = .separate
        XCTAssertFalse(preferences.clipboardLinkMode.importsClipboardCopies)
        XCTAssertFalse(preferences.clipboardLinkMode.mirrorsSelectionsToClipboard)

        preferences.clipboardLinkMode = .importCopies
        XCTAssertTrue(preferences.clipboardLinkMode.importsClipboardCopies)
        XCTAssertFalse(preferences.clipboardLinkMode.mirrorsSelectionsToClipboard)

        preferences.clipboardLinkMode = .mirrorSelections
        XCTAssertFalse(preferences.clipboardLinkMode.importsClipboardCopies)
        XCTAssertTrue(preferences.clipboardLinkMode.mirrorsSelectionsToClipboard)
    }

    func testPasteboardSnapshotPlainTextAndFileSelectionPreviews() {
        let item = NSPasteboardItem()
        item.setString("  alpha\n beta  ", forType: .string)

        let textSnapshot = PasteboardSnapshot(items: [item])
        XCTAssertEqual(textSnapshot.plainText, "  alpha\n beta  ")
        XCTAssertEqual(textSnapshot.clipboardFreePasteText, "  alpha\n beta  ")
        XCTAssertEqual(textSnapshot.previewText, "alpha beta")

        let files = [
            URL(fileURLWithPath: "/tmp/Alpha.txt"),
            URL(fileURLWithPath: "/tmp/Beta.txt"),
            URL(fileURLWithPath: "/tmp/Gamma.txt"),
            URL(fileURLWithPath: "/tmp/Delta.txt"),
        ]
        let fileSnapshot = PasteboardSnapshot(items: [], fileURLs: files)
        XCTAssertEqual(fileSnapshot.previewText, "Alpha.txt, Beta.txt, Gamma.txt, +1 more")
        XCTAssertEqual(fileSnapshot.fileSelectionBadgeText, "4 files")
        XCTAssertNil(fileSnapshot.clipboardFreePasteText)
    }

    func testPasteTransportKeepsTextClipboardFreeAndPreservesRichPayloadBoundary() {
        let textItem = SelectionItem(
            payload: .text("alpha"),
            preview: "alpha",
            sourceAppName: "Test",
            sourceBundleIdentifier: nil,
            capturedAt: Date(timeIntervalSince1970: 100),
            isClipboardCopy: false
        )

        switch textItem.pasteTransport {
        case .clipboardFreeText(let text):
            XCTAssertEqual(text, "alpha")
        case .pasteboard:
            XCTFail("Plain text should not require clipboard paste transport")
        }

        let plainPasteboardItem = NSPasteboardItem()
        plainPasteboardItem.setString(" beta ", forType: .string)
        let plainPasteboardSelection = SelectionItem(
            payload: .pasteboard(PasteboardSnapshot(items: [plainPasteboardItem])),
            preview: "beta",
            sourceAppName: "Test",
            sourceBundleIdentifier: nil,
            capturedAt: Date(timeIntervalSince1970: 101),
            isClipboardCopy: true
        )

        switch plainPasteboardSelection.pasteTransport {
        case .clipboardFreeText(let text):
            XCTAssertEqual(text, " beta ")
        case .pasteboard:
            XCTFail("Plain text pasteboard snapshots should stay clipboard-free")
        }

        let richItem = NSPasteboardItem()
        richItem.setString("gamma", forType: .string)
        richItem.setData(Data("{\\rtf1 gamma}".utf8), forType: .rtf)
        let richSelection = SelectionItem(
            payload: .pasteboard(PasteboardSnapshot(items: [richItem])),
            preview: "gamma",
            sourceAppName: "Test",
            sourceBundleIdentifier: nil,
            capturedAt: Date(timeIntervalSince1970: 102),
            isClipboardCopy: true
        )

        switch richSelection.pasteTransport {
        case .clipboardFreeText:
            XCTFail("Rich pasteboard snapshots need clipboard transport to preserve formatting")
        case .pasteboard:
            break
        }
    }

    func testClipboardSuppressionReportsReasonOnlyForExpectedObservedChange() {
        let start = Date(timeIntervalSince1970: 100)
        var suppression = ClipboardSuppressionState()

        suppression.suppressProgrammaticChanges(
            reason: "copy diagnostics",
            duration: 3,
            changeCountAtStart: 10,
            now: start
        )

        XCTAssertNil(
            suppression.suppressedProgrammaticClipboardReason(
                currentChangeCount: 10,
                now: start.addingTimeInterval(1.0)
            )
        )
        XCTAssertEqual(
            suppression.suppressedProgrammaticClipboardReason(
                currentChangeCount: 11,
                now: start.addingTimeInterval(1.2)
            ),
            "copy diagnostics"
        )
        XCTAssertNil(
            suppression.suppressedProgrammaticClipboardReason(
                currentChangeCount: 12,
                now: start.addingTimeInterval(2.0)
            )
        )
        XCTAssertNil(
            suppression.suppressedProgrammaticClipboardReason(
                currentChangeCount: 13,
                now: start.addingTimeInterval(3.1)
            )
        )
    }

    func testClipboardSuppressionDoesNotHideUnexpectedChangeBursts() {
        let start = Date(timeIntervalSince1970: 100)
        var suppression = ClipboardSuppressionState()

        suppression.suppressProgrammaticChanges(
            reason: "middle-click paste staging",
            duration: 3,
            changeCountAtStart: 20,
            now: start
        )

        XCTAssertNil(
            suppression.suppressedProgrammaticClipboardReason(
                currentChangeCount: 22,
                now: start.addingTimeInterval(0.4)
            )
        )
        XCTAssertNil(
            suppression.suppressedProgrammaticClipboardReason(
                currentChangeCount: 23,
                now: start.addingTimeInterval(0.5)
            )
        )
    }

    func testClipboardSuppressionCanBeClearedAfterAdoptingPasteboardState() {
        let start = Date(timeIntervalSince1970: 100)
        var suppression = ClipboardSuppressionState()

        suppression.suppressProgrammaticChanges(
            reason: "temporary paste restore",
            duration: 3,
            changeCountAtStart: 20,
            now: start
        )
        suppression.clear()

        XCTAssertNil(
            suppression.suppressedProgrammaticClipboardReason(
                currentChangeCount: 21,
                now: start.addingTimeInterval(1.0)
            )
        )
    }

    func testInteractionDiagnosticsTracksNativeClipboardDefaultProbe() {
        let diagnostics = InteractionDiagnostics()

        XCTAssertFalse(diagnostics.nativeClipboardDefaultProbePassed)
        XCTAssertEqual(diagnostics.lastNativeClipboardDefaultProbe, "Native clipboard default probe has not run yet")

        diagnostics.recordNativeClipboardDefaultProbe("Waiting", passed: false)
        XCTAssertEqual(diagnostics.lastNativeClipboardDefaultProbe, "Waiting")
        XCTAssertFalse(diagnostics.nativeClipboardDefaultProbePassed)

        diagnostics.recordNativeClipboardDefaultProbe(
            "Normal clipboard copy stayed out of Primary while Separate", passed: true)
        XCTAssertEqual(
            diagnostics.lastNativeClipboardDefaultProbe,
            "Normal clipboard copy stayed out of Primary while Separate"
        )
        XCTAssertTrue(diagnostics.nativeClipboardDefaultProbePassed)

        diagnostics.resetRuntimeEvidence()
        XCTAssertFalse(diagnostics.nativeClipboardDefaultProbePassed)
        XCTAssertEqual(diagnostics.lastNativeClipboardDefaultProbe, "Native clipboard default probe has not run yet")
    }

    func testClipboardRestorePolicyProtectsNewerUserClipboardChanges() {
        XCTAssertTrue(
            ClipboardRestorePolicy.shouldRestore(
                stagedChangeCount: 12,
                currentChangeCount: 12
            )
        )
        XCTAssertFalse(
            ClipboardRestorePolicy.shouldRestore(
                stagedChangeCount: 12,
                currentChangeCount: 13
            )
        )
    }
    func testRichMultiItemClipboardSurvivesRepeatedTemporaryWritesAndRestoration() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("com.abel.primarypaste.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let restorer = ClipboardRestorer(pasteboard: board)
        let first = NSPasteboardItem()
        first.setString("  formatted text\n", forType: .string)
        first.setData(Data("{\\rtf1 formatted text}".utf8), forType: .rtf)
        let second = NSPasteboardItem()
        second.setData(Data([0, 1, 2, 255]), forType: .png)
        let original = PasteboardSnapshot(items: [first, second])
        restorer.write(original)
        let saved = restorer.snapshot()
        XCTAssertEqual(saved.items.count, 2)
        XCTAssertEqual(saved.items[0].string(forType: .string), "  formatted text\n")
        XCTAssertEqual(saved.items[0].data(forType: .rtf), first.data(forType: .rtf))
        XCTAssertEqual(saved.items[1].data(forType: .png), Data([0, 1, 2, 255]))
        for _ in 0..<3 {
            restorer.writeTextForTemporaryPaste("temporary")
            XCTAssertTrue(restorer.snapshot().isTransient)
            restorer.restore(saved)
            XCTAssertTrue(restorer.snapshot().hasSamePayload(as: saved))
            XCTAssertFalse(restorer.snapshot().isTransient)
        }
        XCTAssertEqual(board.pasteboardItems?.count, 2)
    }

    func testFileClipboardRestorationRetainsExtraRepresentations() {
        let board = NSPasteboard(name: NSPasteboard.Name("com.abel.primarypaste.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let restorer = ClipboardRestorer(pasteboard: board)
        let url = URL(fileURLWithPath: "/tmp/primary-paste-test.txt")
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(Data([5, 8, 13]), forType: NSPasteboard.PasteboardType("test.extra"))
        let snapshot = PasteboardSnapshot(items: [item], fileURLs: [url])
        restorer.writeSnapshotForTemporaryPaste(snapshot)
        XCTAssertEqual(
            restorer.snapshot().items.first?.data(forType: NSPasteboard.PasteboardType("test.extra")), Data([5, 8, 13]))
        restorer.write(snapshot)
        XCTAssertEqual(
            restorer.snapshot().items.first?.data(forType: NSPasteboard.PasteboardType("test.extra")), Data([5, 8, 13]))
    }

    func testClipboardOperationsRequireMatchingOwnerToRelease() throws {
        let restorer = ClipboardRestorer()
        let first = try XCTUnwrap(restorer.beginTemporaryOperation())
        XCTAssertNil(restorer.beginTemporaryOperation())
        restorer.endTemporaryOperation(UUID())
        XCTAssertTrue(restorer.isTemporaryOperationActive)
        restorer.endTemporaryOperation(first)
        XCTAssertFalse(restorer.isTemporaryOperationActive)
        XCTAssertNotNil(restorer.beginTemporaryOperation())
    }

    func testMultipleTextItemsStayOnPasteboardTransportAndPreserveWhitespace() {
        let first = NSPasteboardItem()
        first.setString("  alpha\n", forType: .string)
        let second = NSPasteboardItem()
        second.setString("beta", forType: .string)
        let snapshot = PasteboardSnapshot(items: [first, second])
        XCTAssertEqual(snapshot.plainText, "  alpha\n")
        XCTAssertNil(snapshot.clipboardFreePasteText)
    }

    func testConcealedAndAutogeneratedPayloadsAreRecognizedWithoutInspectingContent() {
        for marker in [
            "org.nspasteboard.ConcealedType", "org.nspasteboard.AutoGeneratedType", "org.nspasteboard.TransientType",
            "com.trolltech.anymime.application--x-nspasteboard-concealed-type",
        ] {
            let item = NSPasteboardItem()
            item.setString("", forType: NSPasteboard.PasteboardType(marker))
            XCTAssertTrue(PasteboardSnapshot(items: [item]).isTransient)
        }
    }

    func testTemporaryTransportsAreConcealedAndExplicitUserCopiesRemainOrdinary() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("com.abel.primarypaste.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let restorer = ClipboardRestorer(pasteboard: board)
        let marker = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let qtMarker = NSPasteboard.PasteboardType("com.trolltech.anymime.application--x-nspasteboard-concealed-type")
        restorer.writeTextForUserClipboard("ordinary copy")
        let original = restorer.snapshot()
        restorer.writeTextForTemporaryPaste("temporary text")
        XCTAssertTrue(try XCTUnwrap(board.pasteboardItems?.first).types.contains(marker))
        XCTAssertTrue(try XCTUnwrap(board.pasteboardItems?.first).types.contains(qtMarker))

        let first = NSPasteboardItem()
        first.setString("rich text", forType: .string)
        first.setData(Data("{\\rtf1 rich text}".utf8), forType: .rtf)
        let second = NSPasteboardItem()
        second.setString("file:///tmp/disposable.txt", forType: .fileURL)
        restorer.writeSnapshotForTemporaryPaste(PasteboardSnapshot(items: [first, second]))
        XCTAssertEqual(board.pasteboardItems?.count, 2)
        XCTAssertTrue(try XCTUnwrap(board.pasteboardItems).allSatisfy { $0.types.contains(marker) })
        XCTAssertTrue(try XCTUnwrap(board.pasteboardItems).allSatisfy { $0.types.contains(qtMarker) })
        XCTAssertEqual(board.pasteboardItems?.first?.data(forType: .rtf), first.data(forType: .rtf))

        restorer.restore(original)
        XCTAssertTrue(restorer.snapshot().hasSamePayload(as: original))
        XCTAssertFalse(try XCTUnwrap(board.pasteboardItems?.first).types.contains(marker))
        XCTAssertFalse(try XCTUnwrap(board.pasteboardItems?.first).types.contains(qtMarker))
        restorer.writeTextForUserClipboard("explicit mirror or copy")
        XCTAssertFalse(restorer.snapshot().isTransient)
    }

}
