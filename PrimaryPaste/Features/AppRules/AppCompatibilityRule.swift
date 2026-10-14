import Foundation

enum AppTextIntegrationMode: String, CaseIterable, Codable, Identifiable {
    case strictAXOnly
    case compatibilityPasteOnly
    case compatibilityPasteAndCopySelection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strictAXOnly:
            return "Standard"
        case .compatibilityPasteOnly:
            return "Paste fallback"
        case .compatibilityPasteAndCopySelection:
            return "Paste and selection fallback"
        }
    }

    var detail: String {
        switch self {
        case .strictAXOnly:
            return "Paste only when macOS identifies an editable text field."
        case .compatibilityPasteOnly:
            return "Click the target and use Cmd+V when this app hides editable fields."
        case .compatibilityPasteAndCopySelection:
            return "Also use temporary Cmd+C after drag selections in this app."
        }
    }

    var enablesCompatibilityPaste: Bool {
        self != .strictAXOnly
    }

    var enablesCompatibilityCopySelection: Bool {
        self == .compatibilityPasteAndCopySelection
    }
}

struct AppCompatibilityRule: Codable, Equatable, Identifiable {
    static let copySelectionDelayRange = 0...2_000
    static let minDragDistanceRange = 0.0...200.0

    var id: String { bundleIdentifier }

    var bundleIdentifier: String
    var displayName: String
    var integrationMode: AppTextIntegrationMode

    var focusBeforePaste: Bool
    var restoreClipboardAfterPaste: Bool

    var copySelectionDelayMs: Int
    var minDragDistance: Double
    var minSelectionLength: Int
    var maxSelectionLength: Int

    init(
        bundleIdentifier: String,
        displayName: String,
        integrationMode: AppTextIntegrationMode = .strictAXOnly,
        focusBeforePaste: Bool = true,
        restoreClipboardAfterPaste: Bool = true,
        copySelectionDelayMs: Int = 120,
        minDragDistance: Double = 6,
        minSelectionLength: Int = 1,
        maxSelectionLength: Int = 20_000
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.integrationMode = integrationMode
        self.focusBeforePaste = focusBeforePaste
        self.restoreClipboardAfterPaste = restoreClipboardAfterPaste
        self.copySelectionDelayMs = copySelectionDelayMs
        self.minDragDistance = minDragDistance
        self.minSelectionLength = minSelectionLength
        self.maxSelectionLength = maxSelectionLength
    }

    func normalized() -> AppCompatibilityRule? {
        let normalizedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBundleIdentifier.isEmpty else { return nil }
        guard integrationMode != .strictAXOnly else { return nil }

        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDelay = min(
            max(copySelectionDelayMs, Self.copySelectionDelayRange.lowerBound),
            Self.copySelectionDelayRange.upperBound
        )
        let finiteDragDistance = minDragDistance.isFinite ? minDragDistance : 6
        let normalizedDragDistance = min(
            max(finiteDragDistance, Self.minDragDistanceRange.lowerBound),
            Self.minDragDistanceRange.upperBound
        )
        let normalizedMinimumLength = min(
            max(minSelectionLength, 1),
            PreferencesStore.maximumSelectionLengthRange.upperBound
        )
        let normalizedMaximumLength = min(
            max(maxSelectionLength, normalizedMinimumLength),
            PreferencesStore.maximumSelectionLengthRange.upperBound
        )

        return AppCompatibilityRule(
            bundleIdentifier: normalizedBundleIdentifier,
            displayName: normalizedDisplayName.isEmpty ? normalizedBundleIdentifier : normalizedDisplayName,
            integrationMode: integrationMode,
            focusBeforePaste: focusBeforePaste,
            restoreClipboardAfterPaste: restoreClipboardAfterPaste,
            copySelectionDelayMs: normalizedDelay,
            minDragDistance: normalizedDragDistance,
            minSelectionLength: normalizedMinimumLength,
            maxSelectionLength: normalizedMaximumLength
        )
    }
}
