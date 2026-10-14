import AppKit
import ApplicationServices
import Foundation

enum PasteAttemptResult {
    case pasted
    case consumedWithoutPaste
    case passThrough

    var didPaste: Bool {
        if case .pasted = self { return true }
        return false
    }

    var shouldConsumeEvent: Bool {
        switch self {
        case .pasted, .consumedWithoutPaste: return true
        case .passThrough: return false
        }
    }
}

final class PasteController {
    private struct Request {
        let processIdentifier: pid_t
        let target: AppRuleTarget?
        let editableTarget: EditableHitTestResult?
        let preserveClipboard: Bool
        let allowsUnavailableFocus: Bool
        let focusedTarget: AXUIElement?
    }

    private let primaryStore: PrimarySelectionStore
    private let preferences: PreferencesStore
    private let hitTester: EditableHitTester
    private let clipboardRestorer: ClipboardRestorer
    private let appRules: AppRulesEngine
    private let diagnostics: InteractionDiagnostics
    private let licensing: LicenseController
    private var requests: [Request] = []
    private var pendingWork: DispatchWorkItem?
    private var operationID: UUID?
    private var originalClipboard: PasteboardSnapshot?
    private var stagedChangeCount: Int?
    var onProgrammaticPasteboardWrite: (() -> Void)?

    init(
        primaryStore: PrimarySelectionStore,
        preferences: PreferencesStore,
        hitTester: EditableHitTester,
        clipboardRestorer: ClipboardRestorer,
        appRules: AppRulesEngine,
        diagnostics: InteractionDiagnostics,
        licensing: LicenseController
    ) {
        self.primaryStore = primaryStore
        self.preferences = preferences
        self.hitTester = hitTester
        self.clipboardRestorer = clipboardRestorer
        self.appRules = appRules
        self.diagnostics = diagnostics
        self.licensing = licensing
    }

    func pastePrimarySelectionIfAllowed(eventLocation: CGPoint? = nil) -> Bool {
        attemptPrimaryPaste(eventLocation: eventLocation).didPaste
    }

    func attemptPrimaryPaste(eventLocation: CGPoint? = nil) -> PasteAttemptResult {
        let target = pasteTarget(eventLocation: eventLocation)
        guard canRequestPaste(target: target) else { return .passThrough }
        let rule = target.flatMap { appRules.compatibilityRule(for: $0) }
        let compatibilityPaste = rule?.integrationMode.enablesCompatibilityPaste == true
        let editableTarget =
            compatibilityPaste ? nil : hitTester.editableElementAtCurrentPointer(eventLocation: eventLocation)
        guard compatibilityPaste || editableTarget != nil else {
            recordPassThrough("Passed through: pointer was not detected over an editable field", target: target)
            return .passThrough
        }
        guard primaryStore.peekItem() != nil else {
            diagnostics.recordPasteDecision("Consumed: Primary is empty")
            return .consumedWithoutPaste
        }

        if let editableTarget {
            hitTester.focusForPaste(editableTarget)
        } else if rule?.focusBeforePaste == true, let eventLocation {
            hitTester.focusAppAtPoint(eventLocation)
        }
        let pid =
            editableTarget.flatMap { processIdentifier(of: $0.element) }
            ?? appRules.frontmostApplication?.processIdentifier
        guard let pid else { return .passThrough }
        return enqueue(
            Request(
                processIdentifier: pid,
                target: target,
                editableTarget: editableTarget,
                preserveClipboard: rule?.restoreClipboardAfterPaste ?? preferences.preserveClipboard,
                allowsUnavailableFocus: compatibilityPaste,
                focusedTarget: nil
            ))
    }

    func pastePrimarySelectionFromShortcut() {
        pastePrimarySelectionFromFocusedTarget(triggerName: "Shortcut")
    }

    func pastePrimarySelectionFromExternalTrigger() {
        pastePrimarySelectionFromFocusedTarget(triggerName: "External trigger")
    }

    private func pastePrimarySelectionFromFocusedTarget(triggerName: String) {
        let target = appRules.frontmostRuleTarget
        guard canRequestPaste(target: target), let pid = appRules.frontmostApplication?.processIdentifier else {
            return
        }
        let rule = target.flatMap { appRules.compatibilityRule(for: $0) }
        let compatibilityPaste = rule?.integrationMode.enablesCompatibilityPaste == true
        let focused = AccessibilityHelpers.focusedElement()
        if let focused, AccessibilityHelpers.isSecureOrProtected(focused) {
            diagnostics.recordPasteDecision("Blocked \(triggerName.lowercased()): protected field")
            return
        }
        guard compatibilityPaste || focused.map(AccessibilityHelpers.isEditableTextElement) == true else {
            diagnostics.recordPasteDecision("Blocked \(triggerName.lowercased()): focus is not an editable field")
            return
        }
        _ = enqueue(
            Request(
                processIdentifier: pid, target: target, editableTarget: nil,
                preserveClipboard: rule?.restoreClipboardAfterPaste ?? preferences.preserveClipboard,
                allowsUnavailableFocus: compatibilityPaste,
                focusedTarget: focused
            ))
    }

    private func canRequestPaste(target: AppRuleTarget?) -> Bool {
        guard preferences.isEnabled, licensing.allowsProductUse, AXIsProcessTrusted(), !appRules.isScreenLocked else {
            recordPassThrough("Passed through: paste is unavailable, paused, or screen is locked", target: target)
            return false
        }
        guard !appRules.shouldPassThrough(bundleIdentifier: target?.bundleIdentifier) else {
            recordPassThrough("Passed through: target app keeps middle-click native", target: target)
            return false
        }
        return true
    }

    private func enqueue(_ request: Request) -> PasteAttemptResult {
        guard primaryStore.peekItem() != nil else {
            diagnostics.recordPasteDecision("Consumed: Primary is empty")
            return .consumedWithoutPaste
        }
        guard requests.count < PreferencesStore.queueSizeRange.upperBound else {
            diagnostics.recordPasteDecision("Consumed: pending paste limit reached")
            return .consumedWithoutPaste
        }
        requests.append(request)
        if operationID == nil, pendingWork == nil { processNextRequest() }
        return .pasted
    }

    private func processNextRequest() {
        guard let request = requests.first else { return }
        guard requestIsStillAllowed(request, beforePointerFocus: true) else {
            requests.removeFirst()
            diagnostics.recordPasteDecision("Cancelled pending paste: target or settings changed")
            schedule(after: 0) { $0.processNextRequest() }
            return
        }
        guard let id = clipboardRestorer.beginTemporaryOperation() else {
            schedule(after: 0.05) { $0.processNextRequest() }
            return
        }
        operationID = id
        requests.removeFirst()
        guard let item = primaryStore.peekItem() else { finishRequest(); return }
        let mode = preferences.pasteMode
        let clearAfterPaste = preferences.clearAfterPaste
        if let target = request.editableTarget { hitTester.focusForPaste(target, positionCaret: false) }

        schedule(after: request.editableTarget == nil ? 0.02 : 0.06) { owner in
            guard owner.requestIsStillAllowed(request), owner.primaryStore.queue.contains(where: { $0.id == item.id })
            else { owner.finishRequest(); return }
            if case .clipboardFreeText(let text) = item.pasteTransport,
                let target = request.editableTarget,
                target.supportsDirectTextInsertion,
                AccessibilityHelpers.insertText(text, into: target.element)
            {
                owner.primaryStore.didPaste(item, mode: mode, clearAfterPaste: clearAfterPaste)
                owner.recordPasteTarget("Inserted text directly", target: request.target)
                owner.finishRequest()
                return
            }
            owner.stageAndPaste(item, request: request, mode: mode, clearAfterPaste: clearAfterPaste)
        }
    }

    private func stageAndPaste(_ item: SelectionItem, request: Request, mode: PasteMode, clearAfterPaste: Bool) {
        originalClipboard = request.preserveClipboard ? clipboardRestorer.snapshot() : nil
        switch item.pasteTransport {
        case .clipboardFreeText(let text): clipboardRestorer.writeTextForTemporaryPaste(text)
        case .pasteboard(let snapshot): clipboardRestorer.writeSnapshotForTemporaryPaste(snapshot)
        }
        stagedChangeCount = NSPasteboard.general.changeCount
        onProgrammaticPasteboardWrite?()
        let focusedAtStaging = AccessibilityHelpers.focusedElement()
        schedule(after: 0.08) { owner in
            guard owner.requestIsStillAllowed(request),
                owner.primaryStore.queue.contains(where: { $0.id == item.id }),
                owner.stagedChangeCount == NSPasteboard.general.changeCount,
                owner.focusMatches(focusedAtStaging, allowsUnavailableFocus: request.allowsUnavailableFocus),
                owner.sendCommandV()
            else {
                owner.diagnostics.recordPasteDecision("Cancelled pending paste: target or clipboard changed")
                owner.finishRequest()
                return
            }
            owner.primaryStore.didPaste(item, mode: mode, clearAfterPaste: clearAfterPaste)
            owner.recordPasteTarget("Paste command sent", target: request.target)
            owner.schedule(after: 0.72) { $0.finishRequest() }
        }
    }

    private func requestIsStillAllowed(_ request: Request, beforePointerFocus: Bool = false) -> Bool {
        guard preferences.isEnabled, licensing.allowsProductUse, AXIsProcessTrusted(), !appRules.isScreenLocked,
            appRules.frontmostApplication?.processIdentifier == request.processIdentifier,
            !appRules.shouldPassThrough(bundleIdentifier: request.target?.bundleIdentifier)
        else { return false }
        if let focused = AccessibilityHelpers.focusedElement(), AccessibilityHelpers.isSecureOrProtected(focused) {
            // Chrome handles the posted caret click asynchronously. A safe pointer
            // target may still have the previous password field focused here.
            // Recheck focus after settling, before any text or clipboard delivery.
            guard beforePointerFocus, let target = request.editableTarget,
                !AccessibilityHelpers.hasSecureOrProtectedAncestor(target.element)
            else { return false }
        }
        if let focusedTarget = request.focusedTarget, !focusMatches(focusedTarget) { return false }
        if !beforePointerFocus, let target = request.editableTarget,
            !AccessibilityHelpers.focusIsWithin(target.element)
        {
            return false
        }
        return true
    }

    private func schedule(after delay: TimeInterval, action: @escaping (PasteController) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingWork = nil
            action(self)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func finishRequest() {
        if let snapshot = originalClipboard, let changeCount = stagedChangeCount,
            ClipboardRestorePolicy.shouldRestore(
                stagedChangeCount: changeCount, currentChangeCount: NSPasteboard.general.changeCount)
        {
            clipboardRestorer.restore(snapshot)
            onProgrammaticPasteboardWrite?()
        }
        originalClipboard = nil
        stagedChangeCount = nil
        if let id = operationID { clipboardRestorer.endTemporaryOperation(id) }
        operationID = nil
        if !requests.isEmpty { schedule(after: 0) { $0.processNextRequest() } }
    }

    func cancelPendingPastes() {
        pendingWork?.cancel()
        pendingWork = nil
        requests.removeAll()
        finishRequest()
    }

    private func focusMatches(_ expected: AXUIElement?, allowsUnavailableFocus: Bool = false) -> Bool {
        switch (expected, AccessibilityHelpers.focusedElement()) {
        case (let expected?, let current?): return CFEqual(expected, current)
        case (nil, nil): return allowsUnavailableFocus
        default: return false
        }
    }

    private func sendCommandV() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func processIdentifier(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    private func pasteTarget(eventLocation: CGPoint?) -> AppRuleTarget? {
        if let eventLocation, let target = hitTester.ruleTarget(at: eventLocation) { return target }
        return appRules.frontmostRuleTarget
    }

    private func recordPasteTarget(_ decision: String, target: AppRuleTarget? = nil) {
        diagnostics.recordPasteTarget(
            decision: decision,
            targetAppName: target?.displayName ?? appRules.frontmostAppName,
            bundleIdentifier: target?.bundleIdentifier ?? appRules.frontmostBundleIdentifier
        )
    }

    private func recordPassThrough(_ decision: String, target: AppRuleTarget? = nil) {
        diagnostics.recordPastePassThrough(
            decision: decision,
            targetAppName: target?.displayName ?? appRules.frontmostAppName,
            bundleIdentifier: target?.bundleIdentifier ?? appRules.frontmostBundleIdentifier
        )
    }
}
