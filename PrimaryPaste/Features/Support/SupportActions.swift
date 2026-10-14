import AppKit
import Foundation

@MainActor
final class SupportActions {
    private let appState: AppState
    private let clipboardObserver: ClipboardObserver
    private let clipboardRestorer: ClipboardRestorer
    private let privacyFilter: PrivacyFilter
    private let toastPresenter: CaptureToastPresenter

    init(
        appState: AppState,
        clipboardObserver: ClipboardObserver,
        clipboardRestorer: ClipboardRestorer,
        privacyFilter: PrivacyFilter,
        toastPresenter: CaptureToastPresenter
    ) {
        self.appState = appState
        self.clipboardObserver = clipboardObserver
        self.clipboardRestorer = clipboardRestorer
        self.privacyFilter = privacyFilter
        self.toastPresenter = toastPresenter
    }

    private var probeID: UUID?
    private var probeWork: DispatchWorkItem?
    private var probeClipboard: PasteboardSnapshot?
    private var probeChangeCount: Int?
    private var probePrimary: PrimarySelectionStore.StateSnapshot?
    private var probeSample: String?

    func runClipboardLinkProbe() {
        guard probeID == nil, let id = clipboardRestorer.beginTemporaryOperation() else {
            appState.diagnostics.recordClipboardDecision("Clipboard check is waiting for another clipboard operation")
            return
        }
        probeID = id
        probeClipboard = clipboardRestorer.snapshot()
        probePrimary = appState.primaryStore.stateSnapshot()
        let mode = appState.preferences.clipboardLinkMode
        let sample = "Primary Paste clipboard check \(UUID().uuidString.prefix(8))"
        clipboardObserver.start()
        clipboardObserver.suppressProgrammaticChanges(reason: "clipboard link probe", duration: 2)
        clipboardRestorer.writeTextForTemporaryPaste(sample)
        probeChangeCount = NSPasteboard.general.changeCount
        appState.diagnostics.recordClipboardSelfCaptureProbe("Checking the temporary clipboard guard", passed: false)
        appState.diagnostics.recordClipboardLinkModeProbe(
            "Checking \(mode.title)", modeTitle: mode.title, passed: false)

        scheduleProbe(after: 0.8) { owner in
            guard owner.probeIsUnchanged(mode: mode) else { owner.finishClipboardProbe(); return }
            owner.restoreProbeClipboardIfUnchanged()
            owner.clipboardObserver.adoptCurrentPasteboardState()
            owner.appState.diagnostics.recordClipboardSelfCaptureProbe(
                "Temporary clipboard content stayed out of Primary", passed: true)
            let modeSample = "Primary Paste mode check \(UUID().uuidString.prefix(8))"
            owner.probeSample = modeSample
            if mode == .mirrorSelections {
                owner.appState.primaryStore.record(
                    modeSample, sourceAppName: "Primary Paste", sourceBundleIdentifier: Bundle.main.bundleIdentifier)
            } else {
                owner.clipboardRestorer.writeTextForUserClipboard(modeSample)
            }
            owner.probeChangeCount = NSPasteboard.general.changeCount
            owner.scheduleProbe(after: 0.8) { owner in
                guard owner.probeIsUnchanged(mode: mode) else { owner.finishClipboardProbe(); return }
                let captured = owner.appState.primaryStore.current?.preview == modeSample
                let passed: Bool
                switch mode {
                case .separate: passed = !captured
                case .importCopies: passed = captured
                case .mirrorSelections: passed = NSPasteboard.general.string(forType: .string) == modeSample
                }
                owner.appState.diagnostics.recordClipboardLinkModeProbe(
                    passed ? "\(mode.title) behaved as expected" : "\(mode.title) did not pass the clipboard check",
                    modeTitle: mode.title, passed: passed)
                if mode == .separate {
                    owner.appState.diagnostics.recordNativeClipboardDefaultProbe(
                        passed
                            ? "Normal clipboard copy stayed out of Primary while Separate"
                            : "Separate mode imported the check unexpectedly", passed: passed)
                }
                owner.finishClipboardProbe()
            }
        }
    }

    private func probeIsUnchanged(mode: ClipboardLinkMode) -> Bool {
        guard probeChangeCount == NSPasteboard.general.changeCount,
            appState.preferences.clipboardLinkMode == mode,
            appState.preferences.isEnabled, !appState.preferences.isPrivateModeEnabled
        else {
            appState.diagnostics.recordClipboardLinkModeProbe(
                "Check interrupted by a clipboard or settings change", modeTitle: mode.title, passed: false)
            return false
        }
        return true
    }

    private func scheduleProbe(after delay: TimeInterval, action: @escaping (SupportActions) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.probeID != nil else { return }
            self.probeWork = nil
            action(self)
        }
        probeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func restoreProbeClipboardIfUnchanged() {
        guard let snapshot = probeClipboard, probeChangeCount == NSPasteboard.general.changeCount else { return }
        clipboardRestorer.restore(snapshot)
        clipboardObserver.adoptCurrentPasteboardState()
    }

    private func finishClipboardProbe() {
        restoreProbeClipboardIfUnchanged()
        if let sample = probeSample, let baseline = probePrimary {
            let store = appState.primaryStore
            let baselineIDs = Set(baseline.queue.map(\.id))
            let otherItems = store.queue.filter { !baselineIDs.contains($0.id) && $0.preview != sample }
            if otherItems.isEmpty, store.current?.preview == sample {
                store.restore(baseline)
            } else {
                for item in store.queue where item.preview == sample { store.remove(item) }
            }
        }
        if let id = probeID { clipboardRestorer.endTemporaryOperation(id) }
        probeID = nil
        probeClipboard = nil
        probeChangeCount = nil
        probePrimary = nil
        probeSample = nil
        if !appState.preferences.shouldRunClipboardImport { clipboardObserver.stop() }
    }

    func cancelClipboardProbe() {
        probeWork?.cancel()
        probeWork = nil
        finishClipboardProbe()
    }

    func runPrivacyProbe() {
        let sample = "api_key=PRIMARYPASTEFAKEKEY1234567890"
        switch privacyFilter.decision(for: sample) {
        case .allowed:
            appState.diagnostics.recordPrivacyProbe("Allowed sensitive-looking sample", passed: false)
        case .denied(let reason):
            let decision = "Denied sensitive-looking sample: \(reason.diagnosticDescription)"
            if case .sensitive = reason {
                appState.diagnostics.recordPrivacyProbe(decision, passed: true)
            } else {
                appState.diagnostics.recordPrivacyProbe(decision, passed: false)
            }
        }
    }

    func previewCaptureToast() {
        let sample = "Selected text preview from Primary Paste"
        let item = SelectionItem(
            payload: .text(sample),
            preview: sample,
            sourceAppName: "Primary Paste",
            sourceBundleIdentifier: Bundle.main.bundleIdentifier,
            capturedAt: Date(),
            isClipboardCopy: false
        )
        toastPresenter.show(item: item)
    }

    func previewLimitToast() {
        toastPresenter.show(
            notice: CaptureToastNotice(
                sourceAppName: "Finder",
                sourceBundleIdentifier: "com.apple.finder",
                sourceLabel: "Finder selection not captured",
                preview: "\(max(appState.preferences.maximumFileSelectionCount + 1, 51)) Finder items selected",
                badge: "\(appState.preferences.maximumFileSelectionCount) max"
            )
        )
    }

}
