import AppKit
import ApplicationServices
import Foundation

private let selectionEngineAXCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let engine = Unmanaged<SelectionEngine>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async {
        engine.handleAXNotification(notification as String, element: element)
    }
}

final class SelectionEngine {
    private let primaryStore: PrimarySelectionStore
    private let preferences: PreferencesStore
    private let privacyFilter: PrivacyFilter
    private let appRules: AppRulesEngine
    private let diagnostics: InteractionDiagnostics
    private let clipboardRestorer: ClipboardRestorer
    private let noticeHandler: ((CaptureToastNotice) -> Void)?
    var onProgrammaticPasteboardWrite: (() -> Void)?
    var onProgrammaticPasteboardRestore: (() -> Void)?

    private var fallbackTimer: Timer?
    private var axObserver: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedProcessIdentifier: pid_t?
    private var observedFocusedElement: AXUIElement?
    private var workspaceObservers: [NSObjectProtocol] = []

    private var pendingSelection: String?
    private var pendingSourceAppName = ""
    private var pendingSourceBundleIdentifier: String?
    private var pendingRecordWorkItem: DispatchWorkItem?
    private var pendingGestureCaptureWorkItem: DispatchWorkItem?
    private var pendingCompatibilityCopyWorkItem: DispatchWorkItem?
    private var compatibilityCopyRequestID: UUID?
    private var isCompatibilityCopyInFlight = false
    private var isRunning = false
    private var lastLimitNoticeSignature = ""
    private var selectionIntentTracker = SelectionIntentTracker()
    private var intentionalSelectionWindow: TimeInterval {
        Double(preferences.selectionIntentWindowMilliseconds) / 1000.0
    }
    private let postGestureSettleWindow: TimeInterval = 0.3

    init(
        primaryStore: PrimarySelectionStore,
        preferences: PreferencesStore,
        privacyFilter: PrivacyFilter,
        appRules: AppRulesEngine,
        diagnostics: InteractionDiagnostics,
        clipboardRestorer: ClipboardRestorer,
        noticeHandler: ((CaptureToastNotice) -> Void)? = nil
    ) {
        self.primaryStore = primaryStore
        self.preferences = preferences
        self.privacyFilter = privacyFilter
        self.appRules = appRules
        self.diagnostics = diagnostics
        self.clipboardRestorer = clipboardRestorer
        self.noticeHandler = noticeHandler
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        isRunning = true
        observeWorkspaceActivation()
        refreshObservedApplication()
        startFallbackPolling()
    }

    func stop() {
        isRunning = false
        selectionIntentTracker = SelectionIntentTracker()
        pendingSelection = ""
        pendingSourceBundleIdentifier = nil
        pendingRecordWorkItem?.cancel()
        pendingRecordWorkItem = nil
        pendingGestureCaptureWorkItem?.cancel()
        pendingGestureCaptureWorkItem = nil
        pendingCompatibilityCopyWorkItem?.cancel()
        pendingCompatibilityCopyWorkItem = nil
        compatibilityCopyRequestID = nil

        fallbackTimer?.invalidate()
        fallbackTimer = nil

        clearAXObserver()

        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    fileprivate func handleAXNotification(_ notification: String, element: AXUIElement) {
        guard isRunning, canCaptureSelection else { return }
        var notificationPID: pid_t = 0
        guard AXUIElementGetPid(element, &notificationPID) == .success,
            notificationPID == appRules.frontmostApplication?.processIdentifier
        else { return }

        guard selectionCaptureModeAllowsCapture else {
            recordIgnoredAutomaticSelectionChange()
            if notification == kAXFocusedUIElementChangedNotification as String {
                observeFocusedElement(captureImmediately: false)
            }
            return
        }

        if notification == kAXFocusedUIElementChangedNotification as String {
            observeFocusedElement(captureImmediately: shouldCaptureFocusedElementImmediately)
        } else if notification == kAXSelectedTextChangedNotification as String
            || notification == kAXValueChangedNotification as String
        {
            captureSelection(from: element)
        } else {
            captureFocusedSelection()
        }
    }

    private var canCaptureSelection: Bool {
        preferences.shouldRunTextSelectionCapture && AXIsProcessTrusted() && !appRules.isScreenLocked
            && appRules.canCaptureFrontmostApp()
    }

    func noteMouseDragSelectionGesture() {
        noteSelectionGesture(.drag)
    }

    func noteMouseDragSelectionEnded(distance: CGFloat) {
        selectionIntentTracker.endMouseDragSelectionGesture(scope: currentSelectionIntentScope)
        scheduleCaptureAfterGesture()
        scheduleCompatibilityCopySelectionIfNeeded(dragDistance: distance)
    }

    func noteMouseDragSelectionCancelled() {
        selectionIntentTracker.cancelMouseDragSelectionGesture()
    }

    func noteSelectionGesture(_ kind: SelectionIntentKind) {
        selectionIntentTracker.noteSelectionGesture(kind, scope: currentSelectionIntentScope)
        if kind != .drag { scheduleCaptureAfterGesture() }
    }

    private func scheduleCaptureAfterGesture() {
        pendingGestureCaptureWorkItem?.cancel()
        let scope = currentSelectionIntentScope
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingGestureCaptureWorkItem = nil
            guard self.isRunning, self.currentSelectionIntentScope == scope else { return }
            // Some editors never emit AX selection notifications. Read once after
            // the app handles the gesture, while its deliberate-selection window is open.
            self.captureFocusedSelection()
        }
        pendingGestureCaptureWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    private func observeWorkspaceActivation() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshObservedApplication()
        }
        workspaceObservers.append(observer)
    }

    private func startFallbackPolling() {
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fallbackPoll()
        }
        if let fallbackTimer {
            RunLoop.main.add(fallbackTimer, forMode: .common)
        }
    }

    private func fallbackPoll() {
        guard canCaptureSelection else { return }
        refreshObservedApplicationIfNeeded()
        captureFocusedSelection()
    }

    private func refreshObservedApplicationIfNeeded() {
        guard let frontmostPID = appRules.frontmostApplication?.processIdentifier else {
            clearAXObserver()
            return
        }
        guard observedProcessIdentifier != frontmostPID else { return }
        refreshObservedApplication()
    }

    private func refreshObservedApplication() {
        pendingRecordWorkItem?.cancel()
        pendingRecordWorkItem = nil
        pendingSelection = ""
        clearAXObserver()
        guard canCaptureSelection else { return }
        guard let app = appRules.frontmostApplication else { return }
        let frontmostPID = app.processIdentifier
        AccessibilityHelpers.prepareApplication(app)

        var observer: AXObserver?
        guard AXObserverCreate(frontmostPID, selectionEngineAXCallback, &observer) == .success, let observer else {
            captureFocusedSelection()
            return
        }

        let application = AXUIElementCreateApplication(frontmostPID)
        axObserver = observer
        observedApplication = application
        observedProcessIdentifier = frontmostPID

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )

        addNotification(kAXFocusedUIElementChangedNotification as String, to: application)
        addNotification(kAXSelectedTextChangedNotification as String, to: application)
        addNotification(kAXValueChangedNotification as String, to: application)
        observeFocusedElement(captureImmediately: shouldCaptureFocusedElementImmediately)
    }

    private func observeFocusedElement(captureImmediately: Bool = true) {
        guard let observer = axObserver else { return }

        if let observedFocusedElement {
            AXObserverRemoveNotification(
                observer,
                observedFocusedElement,
                kAXSelectedTextChangedNotification as CFString
            )
            AXObserverRemoveNotification(
                observer,
                observedFocusedElement,
                kAXValueChangedNotification as CFString
            )
        }

        observedFocusedElement = AccessibilityHelpers.focusedElement()
        guard let focusedElement = observedFocusedElement else { return }
        addNotification(kAXSelectedTextChangedNotification as String, to: focusedElement)
        addNotification(kAXValueChangedNotification as String, to: focusedElement)
        if captureImmediately {
            captureSelection(from: focusedElement)
        }
    }

    private func clearAXObserver() {
        if let observer = axObserver {
            if let observedApplication {
                AXObserverRemoveNotification(
                    observer,
                    observedApplication,
                    kAXFocusedUIElementChangedNotification as CFString
                )
                AXObserverRemoveNotification(
                    observer,
                    observedApplication,
                    kAXSelectedTextChangedNotification as CFString
                )
                AXObserverRemoveNotification(
                    observer,
                    observedApplication,
                    kAXValueChangedNotification as CFString
                )
            }

            if let observedFocusedElement {
                AXObserverRemoveNotification(
                    observer,
                    observedFocusedElement,
                    kAXSelectedTextChangedNotification as CFString
                )
                AXObserverRemoveNotification(
                    observer,
                    observedFocusedElement,
                    kAXValueChangedNotification as CFString
                )
            }

            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }

        axObserver = nil
        observedApplication = nil
        observedProcessIdentifier = nil
        observedFocusedElement = nil
    }

    private func addNotification(_ notification: String, to element: AXUIElement) {
        guard let observer = axObserver else { return }
        AXObserverAddNotification(
            observer,
            element,
            notification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func captureFocusedSelection() {
        guard let focusedElement = AccessibilityHelpers.focusedElement() else { return }
        captureSelection(from: focusedElement)
    }

    private func captureSelection(from element: AXUIElement) {
        // AX notifications arrive throughout a drag. Retain only the settled
        // selection, so one gesture cannot fill a queue with partial strings.
        guard selectionIntentTracker.activeMouseDragSelectionGesture == nil else { return }
        guard canCaptureSelection else { return }
        guard selectionCaptureModeAllowsCapture else { return }
        guard !AccessibilityHelpers.isSecureOrProtected(element) else { return }
        guard let selectedText = AccessibilityHelpers.selectedTextNear(element) else { return }
        switch privacyFilter.decision(for: selectedText) {
        case .allowed:
            lastLimitNoticeSignature = ""
        case .denied(let reason):
            handleRejectedSelection(reason)
            return
        }

        if case .text(let currentText) = primaryStore.current?.payload,
            currentText == selectedText,
            primaryStore.current?.sourceBundleIdentifier == appRules.frontmostBundleIdentifier
        {
            return
        }

        if pendingSelection == selectedText, pendingRecordWorkItem != nil {
            return
        }

        pendingSelection = selectedText
        pendingSourceAppName = appRules.frontmostAppName
        pendingSourceBundleIdentifier = appRules.frontmostBundleIdentifier

        pendingRecordWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.recordPendingSelection(matching: selectedText)
        }
        pendingRecordWorkItem = workItem

        let debounceSeconds = Double(preferences.selectionCaptureDebounceMilliseconds) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: workItem)
    }

    private func recordPendingSelection(matching selectedText: String) {
        guard pendingSelection == selectedText else { return }
        defer {
            pendingRecordWorkItem = nil
        }
        guard selectionIntentTracker.activeMouseDragSelectionGesture == nil else { return }

        guard canCaptureSelection else {
            return
        }
        guard appRules.frontmostBundleIdentifier == pendingSourceBundleIdentifier else { return }
        guard appRules.canCapture(bundleIdentifier: pendingSourceBundleIdentifier) else {
            diagnostics.recordSelectionDecision("Blocked pending selection for \(pendingSourceAppName)")
            return
        }
        guard selectionCaptureModeAllowsCapture else {
            diagnostics.recordSelectionDecision("Ignored pending selection after selection gesture expired")
            return
        }
        guard privacyFilter.allows(selectedText) else { return }

        primaryStore.record(
            selectedText,
            sourceAppName: pendingSourceAppName,
            sourceBundleIdentifier: pendingSourceBundleIdentifier
        )

        diagnostics.recordSelectionCapture(
            characterCount: selectedText.count,
            sourceAppName: pendingSourceAppName,
            bundleIdentifier: pendingSourceBundleIdentifier
        )
    }

    private func scheduleCompatibilityCopySelectionIfNeeded(dragDistance: CGFloat) {
        guard isRunning else { return }
        guard !isCompatibilityCopyInFlight else { return }
        guard preferences.shouldRunTextSelectionCapture else { return }
        guard !appRules.isScreenLocked else { return }
        guard appRules.canCaptureFrontmostApp() else { return }
        guard let rule = appRules.compatibilityRuleForFrontmostApp() else { return }
        guard rule.integrationMode.enablesCompatibilityCopySelection else { return }
        guard dragDistance >= CGFloat(rule.minDragDistance) else { return }

        pendingCompatibilityCopyWorkItem?.cancel()
        let requestID = UUID()
        compatibilityCopyRequestID = requestID
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.compatibilityCopyRequestID == requestID else { return }
            self.pendingCompatibilityCopyWorkItem = nil
            self.compatibilityCopyRequestID = nil
            self.captureSelectionByTemporaryCopy(rule: rule)
        }
        pendingCompatibilityCopyWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(rule.copySelectionDelayMs),
            execute: workItem
        )
    }

    private func captureSelectionByTemporaryCopy(rule: AppCompatibilityRule) {
        guard !isCompatibilityCopyInFlight else { return }
        guard preferences.shouldRunTextSelectionCapture else { return }
        guard !appRules.isScreenLocked else { return }
        guard appRules.frontmostBundleIdentifier == rule.bundleIdentifier else { return }
        guard appRules.canCapture(bundleIdentifier: rule.bundleIdentifier) else { return }

        guard let operationID = clipboardRestorer.beginTemporaryOperation() else { return }
        let pasteboard = NSPasteboard.general
        let snapshot = clipboardRestorer.snapshot()
        let beforeChangeCount = pasteboard.changeCount

        isCompatibilityCopyInFlight = true
        onProgrammaticPasteboardWrite?()
        sendCommandC()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
            guard let self else { return }
            let afterChangeCount = pasteboard.changeCount

            defer {
                self.isCompatibilityCopyInFlight = false
                self.clipboardRestorer.endTemporaryOperation(operationID)
                if afterChangeCount != beforeChangeCount,
                    afterChangeCount - beforeChangeCount <= 2,
                    self.appRules.frontmostBundleIdentifier == rule.bundleIdentifier
                {
                    if ClipboardRestorePolicy.shouldRestore(
                        stagedChangeCount: afterChangeCount,
                        currentChangeCount: pasteboard.changeCount
                    ) {
                        self.clipboardRestorer.restore(snapshot)
                        self.onProgrammaticPasteboardRestore?()
                    } else {
                        self.diagnostics.recordSelectionDecision(
                            "Kept a newer clipboard change after compatibility copy in \(rule.displayName)"
                        )
                    }
                }
            }

            guard self.isRunning else { return }
            guard self.preferences.shouldRunTextSelectionCapture else { return }
            guard !self.appRules.isScreenLocked else { return }
            guard self.appRules.frontmostBundleIdentifier == rule.bundleIdentifier else { return }
            guard self.appRules.canCapture(bundleIdentifier: rule.bundleIdentifier) else { return }
            guard afterChangeCount != beforeChangeCount else {
                self.diagnostics.recordSelectionDecision(
                    "Compatibility copy found no clipboard change in \(rule.displayName)")
                return
            }
            let afterString = pasteboard.string(forType: .string)
            guard let text = afterString, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.diagnostics.recordSelectionDecision("Compatibility copy found no text in \(rule.displayName)")
                return
            }
            guard text.count >= rule.minSelectionLength else {
                self.diagnostics.recordSelectionDecision("Compatibility copy was too short in \(rule.displayName)")
                return
            }
            guard text.count <= rule.maxSelectionLength else {
                self.diagnostics.recordSelectionDecision("Compatibility copy was too long in \(rule.displayName)")
                return
            }

            switch self.privacyFilter.decision(for: text) {
            case .allowed:
                break
            case .denied(let reason):
                self.handleRejectedSelection(reason)
                return
            }

            if case .text(let currentText) = self.primaryStore.current?.payload,
                currentText == text,
                self.primaryStore.current?.sourceBundleIdentifier == rule.bundleIdentifier
            {
                return
            }
            self.primaryStore.record(
                text,
                sourceAppName: rule.displayName,
                sourceBundleIdentifier: rule.bundleIdentifier
            )
            self.diagnostics.recordSelectionCapture(
                characterCount: text.count,
                sourceAppName: rule.displayName,
                bundleIdentifier: rule.bundleIdentifier
            )
        }
    }

    private func sendCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private var selectionCaptureModeAllowsCapture: Bool {
        selectionIntentTracker.allowsCapture(
            mode: preferences.selectionCaptureMode,
            manualGestures: preferences.manualSelectionGestures,
            currentScope: currentSelectionIntentScope,
            activeDragWindow: intentionalSelectionWindow,
            settleWindow: postGestureSettleWindow
        )
    }

    private var shouldCaptureFocusedElementImmediately: Bool {
        preferences.selectionCaptureMode == .anySelection
    }

    private var currentSelectionIntentScope: SelectionIntentScope {
        SelectionIntentScope(
            processIdentifier: appRules.frontmostApplication.map { Int($0.processIdentifier) },
            bundleIdentifier: appRules.frontmostBundleIdentifier,
            appName: appRules.frontmostAppName
        )
    }

    private func recordIgnoredAutomaticSelectionChange() {
        diagnostics.recordSelectionDecision("Ignored automatic selection change in \(appRules.frontmostAppName)")
    }

    private func handleRejectedSelection(_ reason: PrivacyFilterDenialReason) {
        switch reason {
        case .tooLong(let maximum, let actual):
            diagnostics.recordSelectionDecision(
                "Too long: \(actual.formatted()) chars. Limit is \(maximum.formatted()).")
            showTextLimitNoticeIfNeeded(actualCount: actual, limit: maximum)
        case .sensitive:
            diagnostics.recordSelectionDecision("Ignored sensitive-looking selection")
        case .privateMode:
            diagnostics.recordSelectionDecision("Ignored because Private Mode is on")
        case .appDisabled:
            diagnostics.recordSelectionDecision("Ignored because Primary Paste is paused")
        case .tooShort(let minimum, let actual):
            diagnostics.recordSelectionDecision(
                "Too short: \(actual.formatted()) chars. Minimum is \(minimum.formatted()).")
        case .empty:
            diagnostics.recordSelectionDecision("Ignored empty selection")
        }
    }

    private func showTextLimitNoticeIfNeeded(actualCount: Int, limit: Int) {
        guard preferences.showCaptureToasts else { return }

        let signature = "\(appRules.frontmostBundleIdentifier ?? appRules.frontmostAppName):\(actualCount):\(limit)"
        guard signature != lastLimitNoticeSignature else { return }
        lastLimitNoticeSignature = signature

        noticeHandler?(
            CaptureToastNotice(
                sourceAppName: appRules.frontmostAppName,
                sourceBundleIdentifier: appRules.frontmostBundleIdentifier,
                sourceLabel: "Text selection not captured",
                preview: "\(actualCount.formatted()) chars selected",
                badge: "\(limit.formatted()) max"
            )
        )
    }
}
