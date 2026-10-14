import AppKit
import ApplicationServices
import Foundation

enum EditableTargetSurface {
    case nativeTextField
    // Electron, WKWebView, and CodeMirror-style editors expose editable descendants inside web content.
    case webBackedEditor

    var title: String {
        switch self {
        case .nativeTextField:
            return "native text field"
        case .webBackedEditor:
            return "web-backed editor"
        }
    }

    var supportsDirectTextInsertion: Bool {
        self == .nativeTextField
    }

    static func classifyAncestors<Element>(
        startingAt element: Element,
        parent: (Element) -> Element?,
        isWebContent: (Element) -> Bool,
        maxDepth: Int = 64
    ) -> EditableTargetSurface {
        var current: Element? = element
        for _ in 0..<maxDepth {
            guard let ancestor = current else { return .nativeTextField }
            if isWebContent(ancestor) { return .webBackedEditor }
            current = parent(ancestor)
        }
        // An incomplete or cyclic ancestry is not proof of a native field.
        // Prefer the editor's normal paste path over rewriting its AX value.
        return current == nil ? .nativeTextField : .webBackedEditor
    }
}

struct EditableHitTestResult {
    let element: AXUIElement
    let clickLocation: CGPoint?
    let candidateLocations: [CGPoint]
    let surface: EditableTargetSurface

    var supportsDirectTextInsertion: Bool {
        surface.supportsDirectTextInsertion
    }
}

private struct EditablePointCandidateGroup {
    let points: [CGPoint]
    let stopAfterNonEditableHit: Bool
}

final class EditableHitTester {
    private let appRules: AppRulesEngine

    init(appRules: AppRulesEngine) {
        self.appRules = appRules
    }

    func isEditableElementAtCurrentPointer(eventLocation: CGPoint? = nil) -> Bool {
        editableElementAtCurrentPointer(eventLocation: eventLocation) != nil
    }

    func editableElementAtCurrentPointer(eventLocation: CGPoint? = nil) -> EditableHitTestResult? {
        guard AXIsProcessTrusted() else { return nil }
        if let app = appRules.frontmostApplication {
            AccessibilityHelpers.prepareApplication(app)
        }

        let candidateGroups = pointCandidateGroups(eventLocation: eventLocation)
        let allCandidates = candidateGroups.flatMap(\.points)
        let clickLocation = eventLocation ?? allCandidates.first

        for group in candidateGroups {
            var didHitElement = false

            for point in group.points {
                guard let element = element(at: point) else { continue }
                didHitElement = true
                if let editable = editableElementOrAncestor(element) {
                    return hitResult(
                        for: editable,
                        clickLocation: clickLocation,
                        candidateLocations: group.points
                    )
                }
                if let editable = editableDescendant(of: element, containingAny: group.points) {
                    return hitResult(
                        for: editable,
                        clickLocation: clickLocation,
                        candidateLocations: group.points,
                        surface: .webBackedEditor
                    )
                }
            }

            if didHitElement && group.stopAfterNonEditableHit {
                return nil
            }
        }

        if let focusedEditable = focusedEditableContainingAnyCandidate(allCandidates) {
            return hitResult(
                for: focusedEditable,
                clickLocation: clickLocation,
                candidateLocations: allCandidates
            )
        }

        return nil
    }

    func ruleTarget(at point: CGPoint) -> AppRuleTarget? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        guard let targetElement = element(at: point, in: systemWide) else { return nil }

        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(targetElement, &processIdentifier) == .success else { return nil }
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else { return nil }
        guard let bundleIdentifier = application.bundleIdentifier else { return nil }

        return AppRuleTarget(
            bundleIdentifier: bundleIdentifier,
            displayName: application.localizedName ?? bundleIdentifier
        )
    }

    private func hitResult(
        for element: AXUIElement,
        clickLocation: CGPoint?,
        candidateLocations: [CGPoint],
        surface: EditableTargetSurface? = nil
    ) -> EditableHitTestResult {
        EditableHitTestResult(
            element: element,
            clickLocation: clickLocation,
            candidateLocations: candidateLocations,
            surface: surface
                ?? EditableTargetSurface.classifyAncestors(
                    startingAt: element,
                    parent: AccessibilityHelpers.parent,
                    isWebContent: AccessibilityHelpers.isWebContentElement
                )
        )
    }

    func focusForPaste(_ result: EditableHitTestResult, positionCaret: Bool = true) {
        AXUIElementSetAttributeValue(
            result.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        // A middle-click positions the caret in both native and web fields.
        // Processing the queued request must not click again or reset that caret.
        guard positionCaret else { return }
        guard let clickLocation = result.clickLocation else { return }
        synthesizeLeftClick(at: clickLocation)
    }

    func focusAppAtPoint(_ point: CGPoint) {
        synthesizeLeftClick(at: point)
    }

    private func element(at point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        if let element = element(at: point, in: systemWide) {
            return element
        }

        if let frontmostApplication = appRules.frontmostApplication {
            let application = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
            return element(at: point, in: application)
        }

        return nil
    }

    private func element(at point: CGPoint, in root: AXUIElement) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &element)
        guard result == .success else { return nil }
        return element
    }

    private func editableElementOrAncestor(_ element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let element = current else { return nil }
            if AccessibilityHelpers.isSecureOrProtected(element) {
                return nil
            }
            if AccessibilityHelpers.isEditableTextElement(element) {
                return element
            }
            current = AccessibilityHelpers.parent(of: element)
        }
        return nil
    }

    private func editableDescendant(of root: AXUIElement, containingAny points: [CGPoint]) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        var nextIndex = 0
        let maxDepth = 6
        let maxNodes = 180

        while nextIndex < queue.count, visited < maxNodes {
            let (element, depth) = queue[nextIndex]
            nextIndex += 1
            visited += 1

            if AccessibilityHelpers.isSecureOrProtected(element) {
                continue
            }

            if depth > 0,
                AccessibilityHelpers.isEditableTextElement(element),
                frame(of: element, containsAny: points)
            {
                return element
            }

            guard depth < maxDepth else { continue }
            for child in AccessibilityHelpers.children(of: element) {
                guard queue.count < maxNodes else { break }
                queue.append((child, depth + 1))
            }
        }

        return nil
    }

    private func frame(of element: AXUIElement, containsAny points: [CGPoint]) -> Bool {
        guard let frame = AccessibilityHelpers.frame(of: element) else { return false }
        let forgivingFrame = frame.insetBy(dx: -10, dy: -10)
        return points.contains { forgivingFrame.contains($0) }
    }

    private func focusedEditableContainingAnyCandidate(_ points: [CGPoint]) -> AXUIElement? {
        guard
            let focused = AccessibilityHelpers.focusedElement(),
            AccessibilityHelpers.isEditableTextElement(focused),
            !AccessibilityHelpers.hasSecureOrProtectedAncestor(focused)
        else {
            return nil
        }

        guard let frame = AccessibilityHelpers.frame(of: focused) else {
            return nil
        }
        let forgivingFrame = frame.insetBy(dx: -12, dy: -12)
        if points.contains(where: { forgivingFrame.contains($0) }) {
            return focused
        }
        return nil
    }

    private func synthesizeLeftClick(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func pointCandidateGroups(eventLocation: CGPoint?) -> [EditablePointCandidateGroup] {
        let mouseLocation = NSEvent.mouseLocation

        if let eventLocation {
            let primaryPoint = primaryAccessibilityPoint(
                eventLocation: eventLocation,
                mouseLocation: mouseLocation
            )
            let fallbackPoints = uniquePoints([
                eventLocation,
                primaryPoint == eventLocation ? convertToAccessibilityPoint(eventLocation) : eventLocation,
                mouseLocation,
                convertToAccessibilityPoint(mouseLocation),
            ]).filter { hypot($0.x - primaryPoint.x, $0.y - primaryPoint.y) >= 1 }

            return [
                EditablePointCandidateGroup(
                    points: [primaryPoint],
                    stopAfterNonEditableHit: true
                ),
                EditablePointCandidateGroup(
                    points: fallbackPoints,
                    stopAfterNonEditableHit: false
                ),
            ].filter { !$0.points.isEmpty }
        }

        return [
            EditablePointCandidateGroup(
                points: uniquePoints([
                    mouseLocation,
                    convertToAccessibilityPoint(mouseLocation),
                ]),
                stopAfterNonEditableHit: false
            )
        ]
    }

    private func primaryAccessibilityPoint(eventLocation: CGPoint, mouseLocation: CGPoint) -> CGPoint {
        let convertedEventLocation = convertToAccessibilityPoint(eventLocation)
        let convertedMouseLocation = convertToAccessibilityPoint(mouseLocation)

        let eventLooksLikeAccessibilityPoint = distance(eventLocation, convertedMouseLocation) <= 3
        let eventLooksLikeAppKitPoint = distance(eventLocation, mouseLocation) <= 3

        if eventLooksLikeAppKitPoint && !eventLooksLikeAccessibilityPoint {
            return convertedEventLocation
        }
        return eventLocation
    }

    private func uniquePoints(_ points: [CGPoint]) -> [CGPoint] {
        points.reduce(into: []) { unique, point in
            guard !unique.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 1 }) else { return }
            unique.append(point)
        }
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func convertToAccessibilityPoint(_ point: CGPoint) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            return point
        }

        return CGPoint(
            x: point.x,
            y: screen.frame.maxY - (point.y - screen.frame.minY)
        )
    }
}
