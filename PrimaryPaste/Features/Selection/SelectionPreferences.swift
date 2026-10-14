import Foundation

enum SelectionCaptureMode: String, CaseIterable, Identifiable {
    case dragSelectionsOnly
    case customManualGestures
    case anySelection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dragSelectionsOnly: "Safe Drag"
        case .customManualGestures: "Custom Gestures"
        case .anySelection: "Everything"
        }
    }

    var detail: String {
        switch self {
        case .dragSelectionsOnly:
            return "Only text you drag-select becomes Primary. Best for everyday use."
        case .customManualGestures:
            return "Add the selection habits you want Primary to notice. Drag selections stay on."
        case .anySelection:
            return "Capture any selected text macOS exposes. Powerful, but can include app-created selections."
        }
    }
}

struct ManualSelectionGestures: Equatable {
    var doubleClick: Bool = false
    var tripleClick: Bool = false
    var shiftArrow: Bool = false
    var commandA: Bool = false

    func allows(_ kind: SelectionIntentKind) -> Bool {
        switch kind {
        case .drag:
            return true
        case .doubleClick:
            return doubleClick
        case .tripleClick:
            return tripleClick
        case .shiftArrow:
            return shiftArrow
        case .commandA:
            return commandA
        }
    }
}
