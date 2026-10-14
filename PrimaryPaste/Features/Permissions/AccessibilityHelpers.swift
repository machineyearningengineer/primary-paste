import AppKit
import ApplicationServices
import Foundation

enum AccessibilityHelpers {
    private static var preparedApplications: [pid_t: String] = [:]

    static func prepareApplication(_ app: NSRunningApplication) {
        guard AXIsProcessTrusted(), let identifier = app.bundleIdentifier else { return }
        let chromiumApplications = [
            "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
            "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
            "company.thebrowser.Browser", "com.openai.codex", "com.microsoft.VSCode",
        ]
        guard chromiumApplications.contains(identifier) else { return }
        let identity = "\(identifier):\(app.launchDate?.timeIntervalSince1970 ?? 0)"
        guard preparedApplications[app.processIdentifier] != identity else { return }
        preparedApplications = preparedApplications.filter {
            NSRunningApplication(processIdentifier: $0.key)?.isTerminated == false
        }
        preparedApplications[app.processIdentifier] = identity
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // Chromium exposes its toolbar before its page tree. Request the page
        // accessibility mode once per process: repeated requests restart Chrome's
        // two-second activation delay. Electron uses the manual attribute too.
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private static func uiElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axValue(from value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success else { return nil }
        return uiElement(from: value)
    }

    static func focusIsWithin(_ target: AXUIElement) -> Bool {
        var current = focusedElement()
        for _ in 0..<8 {
            guard let element = current, !isSecureOrProtected(element) else { return false }
            if CFEqual(element, target) { return true }
            current = parent(of: element)
        }
        return false
    }

    static func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    static func boolAttribute(_ name: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success else { return nil }
        return value as? Bool
    }

    static func isAttributeSettable(_ name: String, on element: AXUIElement) -> Bool {
        var isSettable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, name as CFString, &isSettable)
        return result == .success && isSettable.boolValue
    }

    @discardableResult
    static func setSelectedRange(_ range: NSRange, on element: AXUIElement) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        )
        return result == .success
    }

    static func insertText(_ text: String, into element: AXUIElement) -> Bool {
        guard
            !text.isEmpty,
            isEditableTextElement(element),
            isAttributeSettable(kAXValueAttribute as String, on: element),
            let value = stringAttribute(kAXValueAttribute as String, from: element)
        else {
            return false
        }

        let currentValue = value as NSString
        guard let selectedRange = selectedRange(from: element),
            isValidTextRange(selectedRange, utf16Length: currentValue.length)
        else { return false }

        let insertedLength = (text as NSString).length
        let updatedValue = currentValue.replacingCharacters(in: selectedRange, with: text)
        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            updatedValue as CFTypeRef
        )
        guard result == .success else { return false }

        setSelectedRange(
            NSRange(location: selectedRange.location + insertedLength, length: 0),
            on: element
        )
        return true
    }

    static func isValidTextRange(_ range: NSRange, utf16Length: Int) -> Bool {
        range.location != NSNotFound && range.location >= 0 && range.length >= 0
            && range.location <= utf16Length && range.length <= utf16Length - range.location
    }

    static func selectedText(from element: AXUIElement) -> String? {
        guard !isSecureOrProtected(element) else { return nil }
        if let direct = stringAttribute(kAXSelectedTextAttribute as String, from: element), !direct.isEmpty {
            return direct
        }

        // WebKit exposes page selections as opaque text-marker ranges rather
        // than AXSelectedText or an NSRange within AXValue. Read only that
        // selected range; never fall back to copying the whole page.
        var markerRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
            let markerRange
        {
            var selectedValue: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element, "AXStringForTextMarkerRange" as CFString, markerRange, &selectedValue
            ) == .success,
                let selected = selectedValue as? String, !selected.isEmpty
            {
                return selected
            }
        }

        guard
            let value = stringAttribute(kAXValueAttribute as String, from: element),
            let range = selectedRange(from: element),
            range.location != NSNotFound,
            range.length > 0
        else {
            return nil
        }

        let nsValue = value as NSString
        guard isValidTextRange(range, utf16Length: nsValue.length) else { return nil }
        return nsValue.substring(with: range)
    }

    static func selectedTextNear(_ element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else { break }
            // Treat secure/protected ancestors as a privacy boundary; do not climb out.
            if isSecureOrProtected(candidate) {
                return nil
            }
            if let selected = selectedText(from: candidate), !selected.isEmpty {
                return selected
            }
            current = parent(of: candidate)
        }

        return selectedTextInSubtree(from: element, maxDepth: 4, maxNodes: 120)
    }

    static func selectedTextInSubtree(from root: AXUIElement, maxDepth: Int, maxNodes: Int) -> String? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        var nextIndex = 0

        while nextIndex < queue.count, visited < maxNodes {
            let (element, depth) = queue[nextIndex]
            nextIndex += 1
            visited += 1

            // Skip protected subtrees instead of probing children.
            if isSecureOrProtected(element) {
                continue
            }

            if let selected = selectedText(from: element), !selected.isEmpty {
                return selected
            }

            guard depth < maxDepth else { continue }
            for child in children(of: element).prefix(max(0, maxNodes - queue.count)) {
                queue.append((child, depth + 1))
            }
        }

        return nil
    }

    static func selectedRange(from element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success, let axValue = axValue(from: value) else { return nil }

        var range = CFRange()
        let success = AXValueGetValue(axValue, .cfRange, &range)
        guard success, range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func isSecureOrProtected(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute as String, from: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute as String, from: element) ?? ""

        if role.localizedCaseInsensitiveContains("secure") { return true }
        if subrole.localizedCaseInsensitiveContains("secure") { return true }
        if boolAttribute("AXProtectedContent", from: element) == true { return true }
        return false
    }

    static func hasSecureOrProtectedAncestor(_ element: AXUIElement, maxDepth: Int = 8) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<maxDepth {
            guard let candidate = current else { return false }
            if isSecureOrProtected(candidate) { return true }
            current = parent(of: candidate)
        }
        return false
    }

    static func isEditableTextElement(_ element: AXUIElement) -> Bool {
        guard !isSecureOrProtected(element) else { return false }

        let role = stringAttribute(kAXRoleAttribute as String, from: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute as String, from: element) ?? ""
        let isEditable = boolAttribute("AXEditable", from: element) == true
        let isValueSettable = isAttributeSettable(kAXValueAttribute as String, on: element)
        let isSelectedRangeSettable = isAttributeSettable(kAXSelectedTextRangeAttribute as String, on: element)

        return isEditableTextElement(
            role: role,
            subrole: subrole,
            isEditable: isEditable,
            isValueSettable: isValueSettable,
            isSelectedRangeSettable: isSelectedRangeSettable
        )
    }

    static func isEditableTextElement(
        role: String,
        subrole: String,
        isEditable: Bool,
        isValueSettable: Bool,
        isSelectedRangeSettable: Bool
    ) -> Bool {
        let textRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
        ]

        if role == kAXStaticTextRole as String { return false }
        if textRoles.contains(role) { return true }
        if isEditable { return true }

        let looksTextual =
            role.localizedCaseInsensitiveContains("text")
            || subrole.localizedCaseInsensitiveContains("text")

        if looksTextual && (isValueSettable || isSelectedRangeSettable) {
            return true
        }
        return false
    }

    static func isWebContentElement(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute as String, from: element) ?? ""
        let roleDescription = stringAttribute(kAXRoleDescriptionAttribute as String, from: element) ?? ""
        let description = stringAttribute(kAXDescriptionAttribute as String, from: element) ?? ""

        if role == "AXWebArea" { return true }
        if role.localizedCaseInsensitiveContains("web") { return true }
        if roleDescription.localizedCaseInsensitiveContains("HTML content") { return true }
        if description.localizedCaseInsensitiveContains("HTML content") { return true }
        return false
    }

    static func isSameElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs, rhs)
    }

    static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &value
        )
        guard result == .success else { return nil }
        return uiElement(from: value)
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        )
        guard result == .success, let children = value as? [AXUIElement] else { return [] }
        return children
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        let positionResult = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionRef
        )
        let sizeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeRef
        )

        guard
            positionResult == .success,
            sizeResult == .success,
            let positionAXValue = axValue(from: positionRef),
            let sizeAXValue = axValue(from: sizeRef)
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionAXValue, .cgPoint, &position),
            AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }
}
