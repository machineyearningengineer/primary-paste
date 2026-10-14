import AppKit
import Foundation

final class MouseEventTap {
    private let preferences: PreferencesStore
    private let pasteController: PasteController
    private let diagnostics: InteractionDiagnostics
    private let selectionGestureHandler: (SelectionIntentKind) -> Void
    private let selectionDragEndedHandler: (CGFloat) -> Void
    private let selectionDragCancelledHandler: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var leftMouseDownLocation: CGPoint?
    private var currentLeftDragDistance: CGFloat = 0
    private var didMarkCurrentLeftDrag = false
    private var consumedMiddleMouseDown = false
    private let dragThreshold: CGFloat = 4

    init(
        preferences: PreferencesStore,
        pasteController: PasteController,
        diagnostics: InteractionDiagnostics,
        selectionGestureHandler: @escaping (SelectionIntentKind) -> Void = { _ in },
        selectionDragEndedHandler: @escaping (CGFloat) -> Void = { _ in },
        selectionDragCancelledHandler: @escaping () -> Void = {}
    ) {
        self.preferences = preferences
        self.pasteController = pasteController
        self.diagnostics = diagnostics
        self.selectionGestureHandler = selectionGestureHandler
        self.selectionDragEndedHandler = selectionDragEndedHandler
        self.selectionDragCancelledHandler = selectionDragCancelledHandler
    }

    var isRunning: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    func start() {
        stop()

        let eventTypes = monitoredEventTypes()
        guard !eventTypes.isEmpty else { return }

        let mask = eventTypes.reduce(CGEventMask(0)) { partialResult, eventType in
            partialResult | CGEventMask(1 << eventType.rawValue)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let owner = Unmanaged<MouseEventTap>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    owner.reenableTap(after: type)
                    return Unmanaged.passUnretained(event)
                }

                switch type {
                case .leftMouseDown:
                    owner.handleLeftMouseDown(event)
                    return Unmanaged.passUnretained(event)
                case .leftMouseDragged:
                    owner.handleLeftMouseDragged(event)
                    return Unmanaged.passUnretained(event)
                case .leftMouseUp:
                    owner.handleLeftMouseUp()
                    return Unmanaged.passUnretained(event)
                case .keyDown:
                    owner.handleKeyDown(event)
                    return Unmanaged.passUnretained(event)
                case .otherMouseDown:
                    return owner.handleOtherMouseDown(event)
                case .otherMouseUp:
                    if event.getIntegerValueField(.mouseEventButtonNumber) == 2, owner.consumedMiddleMouseDown {
                        owner.consumedMiddleMouseDown = false
                        return nil
                    }
                    return Unmanaged.passUnretained(event)
                default:
                    return Unmanaged.passUnretained(event)
                }
            },
            userInfo: refcon
        )

        guard let eventTap else {
            diagnostics.record(
                DiagnosticEvent(
                    capability: .input,
                    severity: .error,
                    audience: .both,
                    outcome: .failed,
                    code: "mouse-event-tap-create-failed",
                    supportMessage: "Mouse event monitoring could not start"
                )
            )
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        runLoopSource = nil
        if didMarkCurrentLeftDrag { selectionDragCancelledHandler() }
        leftMouseDownLocation = nil
        currentLeftDragDistance = 0
        didMarkCurrentLeftDrag = false
        consumedMiddleMouseDown = false
    }

    private func monitoredEventTypes() -> [CGEventType] {
        var eventTypes: [CGEventType] = []

        if preferences.shouldMonitorMouseSelectionGestures {
            eventTypes.append(contentsOf: [
                .leftMouseDown,
                .leftMouseDragged,
                .leftMouseUp,
            ])
        }

        if preferences.shouldMonitorMiddleClickEvents {
            eventTypes.append(contentsOf: [.otherMouseDown, .otherMouseUp])
        }

        if preferences.shouldMonitorKeyboardSelectionGestures {
            eventTypes.append(.keyDown)
        }

        return eventTypes
    }

    private func handleOtherMouseDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard preferences.isEnabled else {
            return Unmanaged.passUnretained(event)
        }
        guard preferences.middleClickTriggerEnabled else {
            return Unmanaged.passUnretained(event)
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        diagnostics.recordMouseEvent(buttonNumber: buttonNumber, location: event.location)

        guard buttonNumber == 2 else {
            return Unmanaged.passUnretained(event)
        }

        let result = pasteController.attemptPrimaryPaste(eventLocation: event.location)
        consumedMiddleMouseDown = result.shouldConsumeEvent
        if result.shouldConsumeEvent {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleLeftMouseDown(_ event: CGEvent) {
        if didMarkCurrentLeftDrag {
            selectionDragCancelledHandler()
        }
        leftMouseDownLocation = event.location
        currentLeftDragDistance = 0
        didMarkCurrentLeftDrag = false
        noteClickSelectionGesture(from: event)
    }

    private func handleLeftMouseDragged(_ event: CGEvent) {
        guard let leftMouseDownLocation else { return }

        let distance = hypot(
            event.location.x - leftMouseDownLocation.x,
            event.location.y - leftMouseDownLocation.y
        )
        currentLeftDragDistance = max(currentLeftDragDistance, distance)
        guard distance >= dragThreshold else { return }
        didMarkCurrentLeftDrag = true
        selectionGestureHandler(.drag)
    }

    private func handleLeftMouseUp() {
        if didMarkCurrentLeftDrag {
            selectionDragEndedHandler(currentLeftDragDistance)
        }
        leftMouseDownLocation = nil
        currentLeftDragDistance = 0
        didMarkCurrentLeftDrag = false
    }

    private func handleKeyDown(_ event: CGEvent) {
        guard let kind = keyboardSelectionGestureKind(event) else { return }
        selectionGestureHandler(kind)
    }

    private func noteClickSelectionGesture(from event: CGEvent) {
        let clickState = event.getIntegerValueField(.mouseEventClickState)
        if clickState >= 3 {
            selectionGestureHandler(.tripleClick)
        } else if clickState == 2 {
            selectionGestureHandler(.doubleClick)
        }
    }

    private func keyboardSelectionGestureKind(_ event: CGEvent) -> SelectionIntentKind? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isArrowKey = (123...126).contains(keyCode)
        let isSelectAll = keyCode == 0 && flags.contains(.maskCommand)

        if isSelectAll {
            return .commandA
        }
        if isArrowKey && flags.contains(.maskShift) {
            return .shiftArrow
        }
        return nil
    }

    private func reenableTap(after reason: CGEventType) {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)

        let reasonDescription = reason == .tapDisabledByTimeout ? "timeout" : "user input"
        diagnostics.record(
            DiagnosticEvent(
                capability: .input,
                severity: .notice,
                audience: .both,
                outcome: .recovered,
                code: "mouse-event-tap-reenabled",
                supportMessage: "Middle-click event monitoring restarted after \(reasonDescription)",
                metadata: .init(state: reasonDescription)
            )
        )
    }
}
