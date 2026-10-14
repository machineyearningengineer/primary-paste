import Foundation

enum PasteMode: String, CaseIterable, Identifiable {
    case latest
    case queue
    case stack
    case cycle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: "Latest"
        case .queue: "Queue"
        case .stack: "Stack"
        case .cycle: "Cycle"
        }
    }
}
