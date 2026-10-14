import Foundation

enum PrivacyFilterDecision {
    case allowed
    case denied(PrivacyFilterDenialReason)

    var isAllowed: Bool {
        if case .allowed = self {
            return true
        }
        return false
    }
}

enum PrivacyFilterDenialReason {
    case appDisabled
    case privateMode
    case tooShort(minimum: Int, actual: Int)
    case tooLong(maximum: Int, actual: Int)
    case empty
    case sensitive

    var diagnosticDescription: String {
        switch self {
        case .appDisabled:
            return "app is paused"
        case .privateMode:
            return "Private Mode is on"
        case .tooShort(let minimum, let actual):
            return "too short (\(actual.formatted()) of \(minimum.formatted()) chars)"
        case .tooLong(let maximum, let actual):
            return "too long (\(actual.formatted()) of \(maximum.formatted()) chars)"
        case .empty:
            return "empty text"
        case .sensitive:
            return "sensitive-looking text"
        }
    }
}

final class PrivacyFilter {
    private let preferences: PreferencesStore

    private static let sensitivePatterns = [
        #"sk-[A-Za-z0-9_\-]{20,}"#,
        #"(?i)(?:api|secret|token|key)[_\- ]?[=:]\s*[A-Za-z0-9_\-]{16,}"#,
        #"\b(?:\d[ -]*?){13,19}\b"#,
        #"\b\d{6}\b"#,
        #"\b[A-Z0-9]{4}(?:-[A-Z0-9]{4}){3,}\b"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    func allows(_ text: String) -> Bool {
        decision(for: text).isAllowed
    }

    func decision(for text: String) -> PrivacyFilterDecision {
        guard preferences.isEnabled else { return .denied(.appDisabled) }
        guard !preferences.isPrivateModeEnabled else { return .denied(.privateMode) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .denied(.empty) }
        guard trimmed.count >= preferences.minimumSelectionLength else {
            return .denied(.tooShort(minimum: preferences.minimumSelectionLength, actual: trimmed.count))
        }
        if preferences.maximumSelectionLength > 0 {
            guard text.count <= preferences.maximumSelectionLength else {
                return .denied(.tooLong(maximum: preferences.maximumSelectionLength, actual: text.count))
            }
        }

        guard preferences.sensitiveTextFiltering else { return .allowed }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let isSensitive = Self.sensitivePatterns.contains { pattern in
            pattern.firstMatch(in: text, range: range) != nil
        }
        return isSensitive ? .denied(.sensitive) : .allowed
    }
}
