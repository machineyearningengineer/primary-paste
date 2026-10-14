import AppKit
import Foundation

final class FileSelectionObserver {
    private let primaryStore: PrimarySelectionStore
    private let preferences: PreferencesStore
    private let clipboardRestorer: ClipboardRestorer
    private let appRules: AppRulesEngine
    private let permissions: PermissionsCoordinator
    private let diagnostics: InteractionDiagnostics
    private let noticeHandler: ((CaptureToastNotice) -> Void)?

    private let queryQueue = DispatchQueue(label: "com.abel.primarypaste.file-selection")
    private var timer: Timer?
    private var pendingRecordWorkItem: DispatchWorkItem?
    private var pendingURLs: [URL] = []
    private var pendingSignature = ""
    private var lastRecordedSignature = ""
    private var lastLimitNoticeSignature = ""
    private var isQueryInFlight = false
    private var generation = UUID()

    private let finderBundleIdentifier = "com.apple.finder"

    init(
        primaryStore: PrimarySelectionStore,
        preferences: PreferencesStore,
        clipboardRestorer: ClipboardRestorer,
        appRules: AppRulesEngine,
        permissions: PermissionsCoordinator,
        diagnostics: InteractionDiagnostics,
        noticeHandler: ((CaptureToastNotice) -> Void)? = nil
    ) {
        self.primaryStore = primaryStore
        self.preferences = preferences
        self.clipboardRestorer = clipboardRestorer
        self.appRules = appRules
        self.permissions = permissions
        self.diagnostics = diagnostics
        self.noticeHandler = noticeHandler
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.pollFileSelection()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingRecordWorkItem?.cancel()
        pendingRecordWorkItem = nil
        generation = UUID()
        isQueryInFlight = false
        resetPendingState()
    }

    private func pollFileSelection() {
        guard preferences.isEnabled else { return }
        guard !preferences.isPrivateModeEnabled else {
            diagnostics.recordFileSelectionDecision("Paused because Private Mode is on")
            resetPendingState()
            return
        }
        guard preferences.captureFileSelections else {
            diagnostics.recordFileSelectionDecision("Off")
            resetPendingState()
            return
        }
        guard !appRules.isScreenLocked else {
            diagnostics.recordFileSelectionDecision("Paused while screen is locked")
            resetPendingState()
            return
        }
        guard permissions.isFinderAutomationTrusted else {
            diagnostics.recordFileSelectionDecision("Waiting for Finder Automation permission")
            resetPendingState()
            return
        }
        guard appRules.canCaptureFrontmostApp() else {
            diagnostics.recordFileSelectionDecision("Blocked for \(appRules.frontmostAppName)")
            return
        }
        guard appRules.frontmostBundleIdentifier == finderBundleIdentifier else {
            diagnostics.recordFileSelectionDecision("Waiting for Finder or Desktop")
            resetPendingState()
            return
        }
        guard !isEditingTextInFinder else {
            diagnostics.recordFileSelectionDecision("Waiting while Finder text is being edited")
            resetPendingState()
            return
        }
        guard !isQueryInFlight else { return }

        isQueryInFlight = true
        let queryGeneration = generation
        queryQueue.async { [weak self] in
            let urls = self?.selectedFinderFileURLs()
            DispatchQueue.main.async {
                guard let self, self.generation == queryGeneration, self.timer != nil else { return }
                self.isQueryInFlight = false
                guard let urls else {
                    self.diagnostics.recordFileSelectionDecision("Finder query failed")
                    self.diagnostics.record(
                        DiagnosticEvent(
                            capability: .fileSelection, severity: .error, audience: .developers, outcome: .failed,
                            code: "finder-query-failed"))
                    return
                }
                self.handleSelectedFileURLs(urls)
            }
        }
    }

    private func handleSelectedFileURLs(_ urls: [URL]) {
        guard preferences.shouldRunFileSelectionCapture, !appRules.isScreenLocked,
            appRules.frontmostBundleIdentifier == finderBundleIdentifier,
            appRules.canCapture(bundleIdentifier: finderBundleIdentifier), permissions.isFinderAutomationTrusted
        else { return }
        guard !isEditingTextInFinder else {
            resetPendingState()
            return
        }
        let existingURLs =
            urls
            .map { $0.standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        let maximumCapturedFileCount = preferences.maximumFileSelectionCount
        guard existingURLs.count <= maximumCapturedFileCount else {
            diagnostics.recordFileSelectionDecision(
                "Too many files selected: \(existingURLs.count). Limit is \(maximumCapturedFileCount).")
            showLimitNoticeIfNeeded(selectedCount: existingURLs.count, limit: maximumCapturedFileCount)
            resetPendingState()
            return
        }

        let selectedURLs = existingURLs
        lastLimitNoticeSignature = ""
        guard !selectedURLs.isEmpty else {
            diagnostics.recordFileSelectionDecision("Finder frontmost, no files selected")
            resetPendingState()
            return
        }

        let signature = selectedURLs.map(\.path).joined(separator: "\n")
        if signature == lastRecordedSignature,
            case .pasteboard(let snapshot) = primaryStore.current?.payload,
            snapshot.fileURLs == selectedURLs
        {
            return
        }
        if pendingSignature == signature, pendingRecordWorkItem != nil {
            return
        }

        pendingURLs = selectedURLs
        pendingSignature = signature

        pendingRecordWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.recordPendingFileSelection(matching: signature)
        }
        pendingRecordWorkItem = workItem

        let debounceSeconds = Double(preferences.selectionCaptureDebounceMilliseconds) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: workItem)
    }

    private func recordPendingFileSelection(matching signature: String) {
        guard pendingSignature == signature else { return }
        guard !pendingURLs.isEmpty else {
            resetPendingState()
            return
        }
        guard preferences.isEnabled,
            !preferences.isPrivateModeEnabled,
            preferences.captureFileSelections,
            !appRules.isScreenLocked,
            permissions.isFinderAutomationTrusted,
            appRules.canCapture(bundleIdentifier: finderBundleIdentifier),
            appRules.frontmostBundleIdentifier == finderBundleIdentifier,
            !isEditingTextInFinder
        else {
            resetPendingState()
            return
        }

        let snapshot = clipboardRestorer.snapshot(fileURLs: pendingURLs)
        primaryStore.record(
            snapshot,
            sourceAppName: "Finder",
            sourceBundleIdentifier: finderBundleIdentifier,
            isClipboardCopy: false
        )

        diagnostics.recordFileSelectionDecision("Captured \(pendingURLs.count) item(s)")
        diagnostics.record(
            DiagnosticEvent(
                capability: .fileSelection,
                outcome: .succeeded,
                code: "finder-selection-captured",
                metadata: .init(itemCount: pendingURLs.count)
            )
        )
        lastRecordedSignature = signature
        pendingRecordWorkItem = nil
    }

    private func resetPendingState() {
        pendingRecordWorkItem?.cancel()
        pendingRecordWorkItem = nil
        pendingURLs = []
        pendingSignature = ""
        lastRecordedSignature = ""
    }

    private var isEditingTextInFinder: Bool {
        guard permissions.isAccessibilityTrusted,
            let focused = AccessibilityHelpers.focusedElement()
        else { return false }
        return AccessibilityHelpers.isEditableTextElement(focused)
    }

    private func selectedFinderFileURLs() -> [URL]? {
        let source = """
            tell application id "com.apple.finder"
                set selectedItems to selection
                set outputURLs to {}
                repeat with selectedItem in selectedItems
                    try
                        set end of outputURLs to URL of selectedItem
                    end try
                end repeat
                return outputURLs
            end tell
            """

        guard let script = NSAppleScript(source: source) else { return [] }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { return nil }

        if result.descriptorType == typeAEList {
            guard result.numberOfItems > 0 else { return [] }
            return (1...result.numberOfItems)
                .compactMap { result.atIndex($0)?.stringValue }
                .compactMap(Self.fileURL(fromFinderURLString:))
        }

        if let path = result.stringValue, !path.isEmpty {
            return Self.fileURL(fromFinderURLString: path).map { [$0] } ?? []
        }

        return []
    }

    private static func fileURL(fromFinderURLString string: String) -> URL? {
        if let url = URL(string: string), url.isFileURL {
            return url
        }
        return URL(fileURLWithPath: string)
    }

    private func showLimitNoticeIfNeeded(selectedCount: Int, limit: Int) {
        guard preferences.showCaptureToasts else { return }

        let signature = "\(selectedCount):\(limit)"
        guard signature != lastLimitNoticeSignature else { return }
        lastLimitNoticeSignature = signature

        noticeHandler?(
            CaptureToastNotice(
                sourceAppName: "Finder",
                sourceBundleIdentifier: finderBundleIdentifier,
                sourceLabel: "Finder selection not captured",
                preview: "\(selectedCount.formatted()) Finder items selected",
                badge: "\(limit.formatted()) max"
            )
        )
    }
}
