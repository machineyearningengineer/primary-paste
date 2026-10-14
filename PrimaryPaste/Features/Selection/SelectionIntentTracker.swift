import Foundation

enum SelectionIntentKind: CaseIterable, Hashable {
    case drag
    case doubleClick
    case tripleClick
    case shiftArrow
    case commandA
}

struct SelectionIntentScope: Equatable {
    let processIdentifier: Int?
    let bundleIdentifier: String?
    let appName: String

    func matches(processIdentifier: Int?, bundleIdentifier: String?, appName: String) -> Bool {
        if let storedProcessIdentifier = self.processIdentifier, let currentProcessIdentifier = processIdentifier {
            return storedProcessIdentifier == currentProcessIdentifier
        }
        if let storedBundleIdentifier = self.bundleIdentifier, let currentBundleIdentifier = bundleIdentifier {
            return storedBundleIdentifier == currentBundleIdentifier
        }
        return self.processIdentifier == nil && processIdentifier == nil && self.bundleIdentifier == nil
            && bundleIdentifier == nil && self.appName == appName
    }
}

struct SelectionIntentMark: Equatable {
    let capturedAt: Date
    let scope: SelectionIntentScope
}

struct SelectionIntentTracker {
    private(set) var activeMouseDragSelectionGesture: SelectionIntentMark?
    private(set) var completedMouseDragSelectionGesture: SelectionIntentMark?
    private(set) var lastGestureMarks: [SelectionIntentKind: SelectionIntentMark] = [:]

    mutating func noteMouseDragSelectionGesture(scope: SelectionIntentScope, now: Date = Date()) {
        activeMouseDragSelectionGesture = SelectionIntentMark(capturedAt: now, scope: scope)
    }

    mutating func endMouseDragSelectionGesture(scope: SelectionIntentScope, now: Date = Date()) {
        let settledScope = activeMouseDragSelectionGesture?.scope ?? scope
        completedMouseDragSelectionGesture = SelectionIntentMark(capturedAt: now, scope: settledScope)
        activeMouseDragSelectionGesture = nil
    }

    mutating func cancelMouseDragSelectionGesture() {
        activeMouseDragSelectionGesture = nil
    }

    mutating func noteSelectionGesture(_ kind: SelectionIntentKind, scope: SelectionIntentScope, now: Date = Date()) {
        if kind == .drag {
            noteMouseDragSelectionGesture(scope: scope, now: now)
            return
        }
        if kind == .tripleClick {
            lastGestureMarks[.doubleClick] = nil
        }
        lastGestureMarks[kind] = SelectionIntentMark(capturedAt: now, scope: scope)
    }

    func allowsCapture(
        mode: SelectionCaptureMode,
        manualGestures: ManualSelectionGestures,
        currentScope: SelectionIntentScope,
        activeDragWindow: TimeInterval,
        settleWindow: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        switch mode {
        case .anySelection:
            return true
        case .dragSelectionsOnly:
            return dragAllowsCapture(
                currentScope: currentScope, activeWindow: activeDragWindow, settleWindow: settleWindow, now: now)
        case .customManualGestures:
            return dragAllowsCapture(
                currentScope: currentScope, activeWindow: activeDragWindow, settleWindow: settleWindow, now: now)
                || SelectionIntentKind.allCases.contains { kind in
                    guard kind != .drag else { return false }
                    return manualGestures.allows(kind)
                        && kindAllowsCapture(kind, currentScope: currentScope, window: settleWindow, now: now)
                }
        }
    }

    private func dragAllowsCapture(
        currentScope: SelectionIntentScope,
        activeWindow: TimeInterval,
        settleWindow: TimeInterval,
        now: Date
    ) -> Bool {
        markAllowsCapture(activeMouseDragSelectionGesture, currentScope: currentScope, window: activeWindow, now: now)
            || markAllowsCapture(
                completedMouseDragSelectionGesture, currentScope: currentScope, window: settleWindow, now: now)
    }

    private func kindAllowsCapture(
        _ kind: SelectionIntentKind,
        currentScope: SelectionIntentScope,
        window: TimeInterval,
        now: Date
    ) -> Bool {
        markAllowsCapture(lastGestureMarks[kind], currentScope: currentScope, window: window, now: now)
    }

    private func markAllowsCapture(
        _ mark: SelectionIntentMark?,
        currentScope: SelectionIntentScope,
        window: TimeInterval,
        now: Date
    ) -> Bool {
        guard let mark else { return false }
        guard now.timeIntervalSince(mark.capturedAt) <= window else { return false }
        return mark.scope.matches(
            processIdentifier: currentScope.processIdentifier,
            bundleIdentifier: currentScope.bundleIdentifier,
            appName: currentScope.appName
        )
    }
}
