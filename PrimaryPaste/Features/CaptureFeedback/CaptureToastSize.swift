import Foundation

enum CaptureToastSize: String, CaseIterable, Identifiable {
    case tiny
    case compact
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiny: "Tiny"
        case .compact: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var detail: String {
        switch self {
        case .tiny:
            return "Closest to the smallest notch-style confirmation."
        case .compact:
            return "Closest to a tiny notch-sized confirmation."
        case .medium:
            return "A little roomier without taking over the top edge."
        case .large:
            return "The previous larger toast size for easier scanning."
        }
    }
}
