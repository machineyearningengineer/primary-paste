import Foundation

enum PrimaryPasteIconVariant: String, CaseIterable, Identifiable {
    case focusFrame
    case selectionSend
    case lineProgress
    case pillCaret
    case cycleLines
    case pCaret
    case dualLane
    case returnLoop
    case platformBridge
    case appPTile
    case handleP
    case mergeSpark
    case selectCursor
    case mintSendTile
    case dropIntoField

    var id: String { rawValue }

    static let defaultMenuBar: PrimaryPasteIconVariant = .focusFrame
    static let defaultAppIcon: PrimaryPasteIconVariant = .appPTile

    var title: String {
        switch self {
        case .focusFrame: "Focus Frame"
        case .selectionSend: "Selection Send"
        case .lineProgress: "Line Progress"
        case .pillCaret: "Pill Caret"
        case .cycleLines: "Cycle Lines"
        case .pCaret: "P Caret"
        case .dualLane: "Dual Lane"
        case .returnLoop: "Return Loop"
        case .platformBridge: "Platform Bridge"
        case .appPTile: "P Tile"
        case .handleP: "Handle P"
        case .mergeSpark: "Merge Spark"
        case .selectCursor: "Select Cursor"
        case .mintSendTile: "Mint Tile"
        case .dropIntoField: "Drop Field"
        }
    }

    var detail: String {
        switch self {
        case .focusFrame:
            return "Selection frame, caret, and text lanes."
        case .selectionSend:
            return "Selected block sent into an insertion point."
        case .lineProgress:
            return "Text lanes with a quiet progress arc."
        case .pillCaret:
            return "One selected pill moving toward the caret."
        case .cycleLines:
            return "Recent lines with a cycle motion."
        case .pCaret:
            return "A direct P mark with an insertion caret."
        case .dualLane:
            return "Two paste paths converging at the caret."
        case .returnLoop:
            return "A return-loop motion around selected lines."
        case .platformBridge:
            return "Abstract bridge between two systems."
        case .appPTile:
            return "Blue rounded app tile with a P/caret mark."
        case .handleP:
            return "Selection handles shaping a P."
        case .mergeSpark:
            return "Dual sources merge into a live caret."
        case .selectCursor:
            return "Selection rectangle with cursor and lines."
        case .mintSendTile:
            return "Soft app tile with selection-to-caret motion."
        case .dropIntoField:
            return "Selected lines dropping into a text field."
        }
    }
}
