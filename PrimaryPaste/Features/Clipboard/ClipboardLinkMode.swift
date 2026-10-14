import Foundation

enum ClipboardLinkMode: String, CaseIterable, Identifiable {
    case separate
    case importCopies
    case mirrorSelections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .separate: "Separate"
        case .importCopies: "Import Copies"
        case .mirrorSelections: "Mirror Selections"
        }
    }

    var detail: String {
        switch self {
        case .separate:
            return "Primary and the normal clipboard stay separate. Cmd+C and Cmd+V keep their normal macOS behavior."
        case .importCopies:
            return "Normal Cmd+C copies also become Primary items."
        case .mirrorSelections:
            return "Captured text selections replace the normal clipboard. Clipboard copies still stay separate."
        }
    }

    var importsClipboardCopies: Bool {
        self == .importCopies
    }

    var mirrorsSelectionsToClipboard: Bool {
        self == .mirrorSelections
    }
}
