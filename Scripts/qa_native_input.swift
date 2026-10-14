import AppKit
import ApplicationServices
import CryptoKit
import Darwin
import Foundation

// Scoped input fallback for the disposable Primary Paste acceptance surfaces.
// Never posts input without existing AX access, an exact app, and a visible window.
// Guest-only: never run this helper against the user's physical desktop.
var virtualMachine: Int32 = 0
var valueSize = MemoryLayout<Int32>.size
let isVirtual = sysctlbyname("kern.hv_vmm_present", &virtualMachine, &valueSize, nil, 0) == 0 && virtualMachine == 1
let ownership = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Primary Paste QA Guest/ownership.json")
let ownershipData = try? Data(contentsOf: ownership)
let ownershipRecord = ownershipData.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
guard isVirtual, ownershipRecord?["owner"] as? String == "primary-paste-qa-guest" else {
    fputs("Input is restricted to the prepared disposable guest. No input was sent.\n", stderr)
    exit(1)
}
let arguments = CommandLine.arguments
func stop(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
if arguments.count == 2, ["clipboard", "clipboard-types"].contains(arguments[1]) {
    var payload = Data()
    var representations: [[String: [String: String]]] = []
    for item in NSPasteboard.general.pasteboardItems ?? [] {
        var hashes: [String: [String: String]] = [:]
        for type in item.types {
            let data = item.data(forType: type) ?? Data()
            payload.append(Data(type.rawValue.utf8))
            payload.append(0)
            payload.append(data)
            payload.append(0)
            var representation: [String: String] = [:]
            if let bytes = item.data(forType: type) {
                representation["data"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            }
            if let string = item.string(forType: type) {
                representation["string"] = SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }
                    .joined()
            }
            hashes[type.rawValue] = representation
        }
        representations.append(hashes)
    }
    if arguments[1] == "clipboard-types" {
        let data = try JSONSerialization.data(withJSONObject: representations, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        print(SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined())
    }
    exit(0)
}
if arguments.count == 1 || (arguments.count == 2 && arguments[1] == "permissions") {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    print("Guest helper Accessibility:", AXIsProcessTrustedWithOptions(options))
    RunLoop.current.run(until: Date().addingTimeInterval(1))
    exit(0)
}
guard arguments.count == 3 || arguments.count == 5 else {
    stop("Usage: QAHelper clipboard|permissions, or BUNDLE inspect|drag|middle|frame [X,Y X,Y]")
}
guard arguments[2] == "inspect" || (arguments.count == 5 && ["drag", "middle", "frame"].contains(arguments[2])) else {
    stop("Only scoped inspection, window layout, drag, and middle-click are supported")
}
let permitted = [
    "com.apple.TextEdit", "com.apple.Safari", "com.apple.finder", "com.google.Chrome", "com.microsoft.edgemac",
    "company.thebrowser.Browser",
    "com.apple.Terminal", "com.mitchellh.ghostty", "com.openai.codex", "com.abel.primarypaste",
]
guard permitted.contains(arguments[1]), AXIsProcessTrusted() else {
    stop("Existing accessibility permission and an allowed app are required. No input was sent.")
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: arguments[1]).first else {
    stop("Target app is not running")
}
func point(_ value: String) -> CGPoint {
    let parts = value.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 2, parts.allSatisfy({ $0.isFinite && $0 >= 0 }) else { stop("Invalid screen point") }
    return CGPoint(x: parts[0], y: parts[1])
}
let target = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(target, 1)
// Inspect the tree the app actually exposes. Enabling Chromium accessibility here
// would mask production startup failures and can restart its activation delay.
var focused: CFTypeRef?
guard AXUIElementCopyAttributeValue(target, kAXFocusedWindowAttribute as CFString, &focused) == .success, let focused
else { stop("Target has no accessible focused window") }
let window = focused as! AXUIElement
var title: CFTypeRef?
AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
let name = title as? String ?? ""
let guestCodex = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Primary Paste QA Guest/Codex/ChatGPT.app")
let disposableCodex =
    arguments[1] == "com.openai.codex" && name == "ChatGPT"
    && app.bundleURL?.resolvingSymlinksInPath() == guestCodex
guard name.contains("Primary Paste") || name.contains("Your First Paste") || disposableCodex else {
    stop("Target is not the named test window")
}
if arguments[2] == "inspect" {
    func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return value
    }
    var visited = 0
    func node(_ element: AXUIElement, _ depth: Int) -> [String: Any] {
        visited += 1
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        var result: [String: Any] = ["index": visited, "role": role, "subrole": subrole]
        if let focused = attribute(element, kAXFocusedAttribute as String) as? Bool {
            result["focused"] = focused
        }
        for (key, name) in [
            (kAXTitleAttribute, "title"), (kAXDescriptionAttribute, "description"),
            (kAXIdentifierAttribute, "identifier"),
        ] {
            if let value = attribute(element, key) as? String { result[name] = String(value.prefix(1024)) }
        }
        if !role.contains("Secure") && !subrole.contains("Secure") {
            for (key, name) in [(kAXValueAttribute, "value"), (kAXSelectedTextAttribute, "selectedText")] {
                if let value = attribute(element, key) as? String { result[name] = String(value.prefix(12000)) }
            }
            if let selected = attribute(element, kAXSelectedTextRangeAttribute as String),
                CFGetTypeID(selected) == AXValueGetTypeID()
            {
                var range = CFRange()
                if AXValueGetValue(selected as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 {
                    result["selectedRange"] = ["location": range.location, "length": range.length]
                }
            }
        }
        if let rect = frame(element) {
            result["frame"] = ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
        }
        if depth < 48, visited < 500, !role.contains("Secure"), !subrole.contains("Secure") {
            var children: [[String: Any]] = []
            for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                guard visited < 500 else { break }
                children.append(node(child, depth + 1))
            }
            result["children"] = children
        }
        return result
    }
    var result = node(window, 0)
    // Content-free hit ancestry helps distinguish a rejected target from a
    // coordinate error. Keep it scoped to the inspected test application.
    if let location = CGEvent(source: nil)?.location {
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(target, Float(location.x), Float(location.y), &hit) == .success {
            var ancestry: [[String: Any]] = []
            var current = hit
            for _ in 0..<8 {
                guard let element = current else { break }
                var entry: [String: Any] = [
                    "role": attribute(element, kAXRoleAttribute as String) as? String ?? "",
                    "subrole": attribute(element, kAXSubroleAttribute as String) as? String ?? "",
                ]
                if let bounds = frame(element) {
                    entry["frame"] = [
                        "x": bounds.minX, "y": bounds.minY,
                        "width": bounds.width, "height": bounds.height,
                    ]
                }
                ancestry.append(entry)
                if let parent = attribute(element, kAXParentAttribute as String),
                    CFGetTypeID(parent) == AXUIElementGetTypeID()
                {
                    current = (parent as! AXUIElement)
                } else {
                    current = nil
                }
            }
            result["pointerHit"] = ancestry
            result["pointer"] = ["x": location.x, "y": location.y]
        }
    }
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}
let from = point(arguments[3]), to = point(arguments[4])
if arguments[2] == "frame" {
    guard to.x > from.x, to.y > from.y, to.x <= 1280, to.y <= 800, from.y >= 24,
        to.x - from.x >= 400, to.y - from.y >= 300
    else { stop("Layout must fit the disposable guest display") }
    var origin = from
    var size = CGSize(width: to.x - from.x, height: to.y - from.y)
    guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size),
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success,
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) == .success
    else { stop("Test window refused the layout") }
    app.activate()
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    print("Named guest test window positioned; inspect its actual bounds.")
    exit(0)
}
let list = [window]
func frame(_ window: AXUIElement) -> CGRect? {
    var position: CFTypeRef?, size: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
        let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero, dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
        AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
        origin.x.isFinite, origin.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
        dimensions.width >= 0, dimensions.height >= 0
    else { return nil }
    return CGRect(origin: origin, size: dimensions)
}
guard list.compactMap(frame).contains(where: { $0.contains(from) && $0.contains(to) }) else {
    stop("Points must lie inside the target's visible window")
}
app.activate()
AXUIElementPerformAction(window, kAXRaiseAction as CFString)
// A fresh Chromium tree takes two seconds to activate. Input must wait for the
// production observer's request; repeatedly requesting it here resets that delay.
RunLoop.current.run(until: Date().addingTimeInterval(2.2))
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
    stop("Target could not become frontmost")
}
func verifyFocusedWindow() {
    var current: CFTypeRef?
    guard AXUIElementCopyAttributeValue(target, kAXFocusedWindowAttribute as CFString, &current) == .success,
        let current, CFEqual(current, window), let bounds = frame(window),
        bounds.contains(from), bounds.contains(to)
    else { stop("Test window focus or bounds changed; no further input was sent") }
}
verifyFocusedWindow()
let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ position: CGPoint, _ button: CGMouseButton) {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
        stop("Target changed; stopped scoped input")
    }
    verifyFocusedWindow()
    guard
        let event = CGEvent(
            mouseEventSource: source, mouseType: type, mouseCursorPosition: position, mouseButton: button)
    else { stop("Could not create input event") }
    event.flags = []
    event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.post(tap: .cghidEventTap)
}
if arguments[2] == "middle" {
    post(.otherMouseDown, from, .center)
    usleep(30_000)
    post(.otherMouseUp, from, .center)
} else {
    post(.leftMouseDown, from, .left)
    for step in 1...20 {
        usleep(20_000)
        let fraction = CGFloat(step) / 20
        post(
            .leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction),
            .left)
    }
    post(.leftMouseUp, to, .left)
}
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
print("Scoped input sent to \(arguments[1]); verify the visible result independently.")
