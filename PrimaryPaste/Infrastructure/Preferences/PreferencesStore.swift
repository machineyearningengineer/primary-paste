import Combine
import Foundation

final class PreferencesStore: ObservableObject {
    private static let appCompatibilityRulesKey = "appCompatibilityRules"

    static let queueSizeRange = 1...50
    static let selectionDebounceRange = 0...900
    static let minimumSelectionLengthRange = 1...500
    static let maximumSelectionLengthRange: ClosedRange<Int> = 500...250_000
    static let maximumFileSelectionCountRange: ClosedRange<Int> = 1...500
    static let defaultSelectionIntentWindowMilliseconds = 6_000
    static let selectionIntentWindowRange: ClosedRange<Int> = 750...12_000
    static let defaultCaptureToastSize: CaptureToastSize = .medium
    static let captureToastDisplaySecondsRange: ClosedRange<Double> = 1.0...4.0
    static let defaultCaptureToastDisplaySeconds = 2.1

    @Published var isEnabled: Bool {
        didSet { persist("isEnabled", isEnabled) }
    }

    @Published var isPrivateModeEnabled: Bool {
        didSet { persist("isPrivateModeEnabled", isPrivateModeEnabled) }
    }

    @Published var launchAtLogin: Bool {
        didSet { persist("launchAtLogin", launchAtLogin) }
    }

    @Published var showSetupOnLaunch: Bool {
        didSet { persist("showSetupOnLaunch", showSetupOnLaunch) }
    }

    @Published var showSupport: Bool {
        didSet { persist("showSupport", showSupport) }
    }

    @Published var showDockIcon: Bool {
        didSet { persist("showDockIcon", showDockIcon) }
    }

    @Published var menuBarIconVariant: PrimaryPasteIconVariant {
        didSet { persist("menuBarIconVariant", menuBarIconVariant.rawValue) }
    }

    @Published var appIconVariant: PrimaryPasteIconVariant {
        didSet { persist("appIconVariant", appIconVariant.rawValue) }
    }

    @Published var showMenuBarStatusText: Bool {
        didSet { persist("showMenuBarStatusText", showMenuBarStatusText) }
    }

    @Published var captureSelections: Bool {
        didSet { persist("captureSelections", captureSelections) }
    }

    @Published var selectionCaptureMode: SelectionCaptureMode {
        didSet { persist("selectionCaptureMode", selectionCaptureMode.rawValue) }
    }

    @Published var captureDoubleClickSelections: Bool {
        didSet { persist("captureDoubleClickSelections", captureDoubleClickSelections) }
    }

    @Published var captureTripleClickSelections: Bool {
        didSet { persist("captureTripleClickSelections", captureTripleClickSelections) }
    }

    @Published var captureShiftArrowSelections: Bool {
        didSet { persist("captureShiftArrowSelections", captureShiftArrowSelections) }
    }

    @Published var captureCommandASelections: Bool {
        didSet { persist("captureCommandASelections", captureCommandASelections) }
    }

    @Published var captureFileSelections: Bool {
        didSet { persist("captureFileSelections", captureFileSelections) }
    }

    @Published var clipboardLinkMode: ClipboardLinkMode {
        didSet { persist("clipboardLinkMode", clipboardLinkMode.rawValue) }
    }

    @Published var showCaptureToasts: Bool {
        didSet { persist("showCaptureToasts", showCaptureToasts) }
    }

    @Published var showToastSourceLabel: Bool {
        didSet { persist("showToastSourceLabel", showToastSourceLabel) }
    }

    @Published var captureToastSize: CaptureToastSize {
        didSet { persist("captureToastSize", captureToastSize.rawValue) }
    }

    @Published var captureToastDisplaySeconds: Double {
        didSet {
            let normalized = Self.normalizedCaptureToastDisplaySeconds(captureToastDisplaySeconds)
            if captureToastDisplaySeconds != normalized {
                captureToastDisplaySeconds = normalized
            }
            persist("captureToastDisplaySeconds", captureToastDisplaySeconds)
        }
    }

    @Published var selectionCaptureDebounceMilliseconds: Int {
        didSet {
            let normalized = Self.clamp(selectionCaptureDebounceMilliseconds, to: Self.selectionDebounceRange)
            if selectionCaptureDebounceMilliseconds != normalized { selectionCaptureDebounceMilliseconds = normalized }
            persist("selectionCaptureDebounceMilliseconds", selectionCaptureDebounceMilliseconds)
        }
    }

    @Published var selectionIntentWindowMilliseconds: Int {
        didSet {
            let normalized = Self.clamp(selectionIntentWindowMilliseconds, to: Self.selectionIntentWindowRange)
            if selectionIntentWindowMilliseconds != normalized { selectionIntentWindowMilliseconds = normalized }
            persist("selectionIntentWindowMilliseconds", selectionIntentWindowMilliseconds)
        }
    }

    @Published var middleClickTriggerEnabled: Bool {
        didSet { persist("middleClickTriggerEnabled", middleClickTriggerEnabled) }
    }

    @Published var keyboardShortcutTriggerEnabled: Bool {
        didSet { persist("keyboardShortcutTriggerEnabled", keyboardShortcutTriggerEnabled) }
    }

    @Published var externalTriggerEnabled: Bool {
        didSet { persist("externalTriggerEnabled", externalTriggerEnabled) }
    }

    @Published var preserveClipboard: Bool {
        didSet { persist("preserveClipboard", preserveClipboard) }
    }

    @Published var plainTextOnly: Bool {
        didSet { persist("plainTextOnly", plainTextOnly) }
    }

    @Published var clearAfterPaste: Bool {
        didSet { persist("clearAfterPaste", clearAfterPaste) }
    }

    @Published var sensitiveTextFiltering: Bool {
        didSet { persist("sensitiveTextFiltering", sensitiveTextFiltering) }
    }

    @Published var minimumSelectionLength: Int {
        didSet {
            let normalized = Self.clamp(minimumSelectionLength, to: Self.minimumSelectionLengthRange)
            if minimumSelectionLength != normalized { minimumSelectionLength = normalized }
            persist("minimumSelectionLength", minimumSelectionLength)
        }
    }

    @Published var maximumSelectionLength: Int {
        didSet {
            let normalized = Self.normalizedMaximumSelectionLength(maximumSelectionLength)
            if maximumSelectionLength != normalized {
                maximumSelectionLength = normalized
            }
            persist("maximumSelectionLength", maximumSelectionLength)
        }
    }

    @Published var maximumFileSelectionCount: Int {
        didSet {
            let normalized = Self.normalizedMaximumFileSelectionCount(maximumFileSelectionCount)
            if maximumFileSelectionCount != normalized {
                maximumFileSelectionCount = normalized
            }
            persist("maximumFileSelectionCount", maximumFileSelectionCount)
        }
    }

    @Published var queueSize: Int {
        didSet {
            let normalized = Self.clamp(queueSize, to: Self.queueSizeRange)
            if queueSize != normalized { queueSize = normalized }
            persist("queueSize", queueSize)
        }
    }

    @Published var pasteMode: PasteMode {
        didSet { persist("pasteMode", pasteMode.rawValue) }
    }

    @Published var blockedBundleIdentifiers: [String] {
        didSet { persist("blockedBundleIdentifiers", blockedBundleIdentifiers) }
    }

    @Published var passThroughBundleIdentifiers: [String] {
        didSet { persist("passThroughBundleIdentifiers", passThroughBundleIdentifiers) }
    }

    @Published var appCompatibilityRules: [AppCompatibilityRule] {
        didSet { persistAppCompatibilityRules() }
    }

    @Published var completedManualVerificationIDs: [String] {
        didSet { persist("completedManualVerificationIDs", completedManualVerificationIDs) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: "isEnabled") as? Bool ?? true
        isPrivateModeEnabled = defaults.object(forKey: "isPrivateModeEnabled") as? Bool ?? false
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        showSetupOnLaunch = defaults.object(forKey: "showSetupOnLaunch") as? Bool ?? false
        showSupport = defaults.object(forKey: "showSupport") as? Bool ?? false
        showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? true
        menuBarIconVariant =
            defaults.string(forKey: "menuBarIconVariant")
            .flatMap(PrimaryPasteIconVariant.init(rawValue:)) ?? .defaultMenuBar
        appIconVariant =
            defaults.string(forKey: "appIconVariant")
            .flatMap(PrimaryPasteIconVariant.init(rawValue:)) ?? .defaultAppIcon
        showMenuBarStatusText = defaults.object(forKey: "showMenuBarStatusText") as? Bool ?? true
        captureSelections = defaults.object(forKey: "captureSelections") as? Bool ?? true
        selectionCaptureMode =
            defaults.string(forKey: "selectionCaptureMode")
            .flatMap(SelectionCaptureMode.init(rawValue:)) ?? .dragSelectionsOnly
        captureDoubleClickSelections = defaults.object(forKey: "captureDoubleClickSelections") as? Bool ?? false
        captureTripleClickSelections = defaults.object(forKey: "captureTripleClickSelections") as? Bool ?? false
        captureShiftArrowSelections = defaults.object(forKey: "captureShiftArrowSelections") as? Bool ?? false
        captureCommandASelections = defaults.object(forKey: "captureCommandASelections") as? Bool ?? false
        captureFileSelections = defaults.object(forKey: "captureFileSelections") as? Bool ?? false
        clipboardLinkMode =
            defaults.string(forKey: "clipboardLinkMode")
            .flatMap(ClipboardLinkMode.init(rawValue:)) ?? .separate
        showCaptureToasts = defaults.object(forKey: "showCaptureToasts") as? Bool ?? true
        showToastSourceLabel = defaults.object(forKey: "showToastSourceLabel") as? Bool ?? false
        captureToastSize =
            defaults.string(forKey: "captureToastSize")
            .flatMap(CaptureToastSize.init(rawValue:)) ?? Self.defaultCaptureToastSize
        captureToastDisplaySeconds = Self.normalizedCaptureToastDisplaySeconds(
            defaults.object(forKey: "captureToastDisplaySeconds") as? Double ?? Self.defaultCaptureToastDisplaySeconds
        )
        selectionCaptureDebounceMilliseconds =
            Self.clamp(
                defaults.object(forKey: "selectionCaptureDebounceMilliseconds") as? Int ?? 40,
                to: Self.selectionDebounceRange)
        selectionIntentWindowMilliseconds = Self.loadSelectionIntentWindowMilliseconds(defaults: defaults)
        middleClickTriggerEnabled = defaults.object(forKey: "middleClickTriggerEnabled") as? Bool ?? true
        keyboardShortcutTriggerEnabled = defaults.object(forKey: "keyboardShortcutTriggerEnabled") as? Bool ?? false
        externalTriggerEnabled = defaults.object(forKey: "externalTriggerEnabled") as? Bool ?? false
        preserveClipboard = defaults.object(forKey: "preserveClipboard") as? Bool ?? true
        plainTextOnly = defaults.object(forKey: "plainTextOnly") as? Bool ?? true
        clearAfterPaste = defaults.object(forKey: "clearAfterPaste") as? Bool ?? false
        sensitiveTextFiltering = defaults.object(forKey: "sensitiveTextFiltering") as? Bool ?? true
        minimumSelectionLength = Self.clamp(
            defaults.object(forKey: "minimumSelectionLength") as? Int ?? 1, to: Self.minimumSelectionLengthRange)
        maximumSelectionLength = Self.normalizedMaximumSelectionLength(
            defaults.object(forKey: "maximumSelectionLength") as? Int ?? 10_000)
        maximumFileSelectionCount = Self.normalizedMaximumFileSelectionCount(
            defaults.object(forKey: "maximumFileSelectionCount") as? Int ?? 50)
        queueSize = Self.clamp(defaults.object(forKey: "queueSize") as? Int ?? 5, to: Self.queueSizeRange)

        let mode = defaults.string(forKey: "pasteMode").flatMap(PasteMode.init(rawValue:))
        pasteMode = mode ?? .latest

        blockedBundleIdentifiers =
            defaults.stringArray(forKey: "blockedBundleIdentifiers") ?? [
                "com.1password.1password",
                "com.agilebits.onepassword7",
                "com.bitwarden.desktop",
                "com.apple.keychainaccess",
            ]
        passThroughBundleIdentifiers = defaults.stringArray(forKey: "passThroughBundleIdentifiers") ?? []
        appCompatibilityRules = Self.loadAppCompatibilityRules(defaults: defaults)
        completedManualVerificationIDs = defaults.stringArray(forKey: "completedManualVerificationIDs") ?? []

    }

    private func persist(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }

    private func persistAppCompatibilityRules() {
        guard let data = try? JSONEncoder().encode(appCompatibilityRules) else { return }
        defaults.set(data, forKey: Self.appCompatibilityRulesKey)
    }

    private static func loadAppCompatibilityRules(defaults: UserDefaults) -> [AppCompatibilityRule] {
        guard
            let data = defaults.data(forKey: appCompatibilityRulesKey),
            let rules = try? JSONDecoder().decode([AppCompatibilityRule].self, from: data)
        else {
            return []
        }
        var normalizedRules: [AppCompatibilityRule] = []
        for rule in rules {
            guard let normalizedRule = rule.normalized() else { continue }
            normalizedRules.removeAll { $0.bundleIdentifier == normalizedRule.bundleIdentifier }
            normalizedRules.append(normalizedRule)
        }
        return normalizedRules
    }

    func compatibilityRule(for bundleIdentifier: String?) -> AppCompatibilityRule? {
        guard let bundleIdentifier else { return nil }
        return appCompatibilityRules.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func setCompatibilityRule(_ rule: AppCompatibilityRule) {
        let bundleIdentifier = rule.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty else { return }
        guard let normalizedRule = rule.normalized() else {
            removeCompatibilityRule(bundleIdentifier: bundleIdentifier)
            return
        }
        if let index = appCompatibilityRules.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
            appCompatibilityRules[index] = normalizedRule
        } else {
            appCompatibilityRules.append(normalizedRule)
        }
    }

    func removeCompatibilityRule(bundleIdentifier: String) {
        appCompatibilityRules.removeAll { $0.bundleIdentifier == bundleIdentifier }
    }

    private static func loadSelectionIntentWindowMilliseconds(defaults: UserDefaults) -> Int {
        guard let storedValue = defaults.object(forKey: "selectionIntentWindowMilliseconds") as? Int else {
            return defaultSelectionIntentWindowMilliseconds
        }

        let normalizedValue = min(
            max(storedValue, selectionIntentWindowRange.lowerBound), selectionIntentWindowRange.upperBound)
        if normalizedValue != storedValue {
            defaults.set(normalizedValue, forKey: "selectionIntentWindowMilliseconds")
        }
        return normalizedValue
    }

    static func normalizedMaximumSelectionLength(_ value: Int) -> Int {
        guard value > 0 else { return 0 }
        return min(max(value, maximumSelectionLengthRange.lowerBound), maximumSelectionLengthRange.upperBound)
    }

    static func normalizedMaximumFileSelectionCount(_ value: Int) -> Int {
        min(max(value, maximumFileSelectionCountRange.lowerBound), maximumFileSelectionCountRange.upperBound)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func normalizedCaptureToastDisplaySeconds(_ value: Double) -> Double {
        guard value.isFinite else { return defaultCaptureToastDisplaySeconds }
        return min(max(value, captureToastDisplaySecondsRange.lowerBound), captureToastDisplaySecondsRange.upperBound)
    }

    var shouldRunClipboardImport: Bool {
        isEnabled && !isPrivateModeEnabled && clipboardLinkMode.importsClipboardCopies
    }

    var shouldRunTextSelectionCapture: Bool {
        isEnabled && captureSelections && !isPrivateModeEnabled
    }

    var shouldRunFileSelectionCapture: Bool {
        isEnabled && captureFileSelections && !isPrivateModeEnabled
    }

    var shouldMonitorMouseSelectionGestures: Bool {
        shouldRunTextSelectionCapture
            && (selectionCaptureMode == .dragSelectionsOnly || selectionCaptureMode == .customManualGestures)
    }

    var shouldMonitorKeyboardSelectionGestures: Bool {
        shouldRunTextSelectionCapture && selectionCaptureMode == .customManualGestures
            && (captureShiftArrowSelections || captureCommandASelections)
    }

    var manualSelectionGestures: ManualSelectionGestures {
        ManualSelectionGestures(
            doubleClick: captureDoubleClickSelections,
            tripleClick: captureTripleClickSelections,
            shiftArrow: captureShiftArrowSelections,
            commandA: captureCommandASelections
        )
    }

    var shouldMonitorMiddleClickEvents: Bool {
        isEnabled && middleClickTriggerEnabled
    }

    var shouldMonitorGlobalEvents: Bool {
        shouldMonitorMouseSelectionGestures || shouldMonitorKeyboardSelectionGestures || shouldMonitorMiddleClickEvents
    }

    var shouldUseAccessibility: Bool {
        isEnabled
            && ((captureSelections && !isPrivateModeEnabled) || middleClickTriggerEnabled
                || keyboardShortcutTriggerEnabled || externalTriggerEnabled)
    }

    func isManualVerificationComplete(_ id: String) -> Bool {
        completedManualVerificationIDs.contains(id)
    }

    func setManualVerification(_ id: String, isComplete: Bool) {
        if isComplete {
            guard !completedManualVerificationIDs.contains(id) else { return }
            completedManualVerificationIDs.append(id)
        } else {
            completedManualVerificationIDs.removeAll { $0 == id }
        }
    }

    func resetManualVerification() {
        completedManualVerificationIDs.removeAll()
    }

    func resetToDefaults() {
        [
            "isEnabled",
            "isPrivateModeEnabled",
            "launchAtLogin",
            "showSetupOnLaunch",
            "showSupport",
            "showDockIcon",
            "menuBarIconVariant",
            "appIconVariant",
            "showMenuBarStatusText",
            "captureSelections",
            "selectionCaptureMode",
            "captureDoubleClickSelections",
            "captureTripleClickSelections",
            "captureShiftArrowSelections",
            "captureCommandASelections",
            "captureFileSelections",
            "clipboardLinkMode",
            "showCaptureToasts",
            "showToastSourceLabel",
            "captureToastSize",
            "captureToastDisplaySeconds",
            "selectionCaptureDebounceMilliseconds",
            "selectionIntentWindowMilliseconds",
            "toastTopOffset",
            "middleClickTriggerEnabled",
            "keyboardShortcutTriggerEnabled",
            "externalTriggerEnabled",
            "preserveClipboard",
            "plainTextOnly",
            "clearAfterPaste",
            "sensitiveTextFiltering",
            "minimumSelectionLength",
            "maximumSelectionLength",
            "maximumFileSelectionCount",
            "queueSize",
            "pasteMode",
            "blockedBundleIdentifiers",
            "passThroughBundleIdentifiers",
            Self.appCompatibilityRulesKey,
            "completedManualVerificationIDs",
        ].forEach { defaults.removeObject(forKey: $0) }

        isEnabled = true
        isPrivateModeEnabled = false
        launchAtLogin = false
        showSetupOnLaunch = false
        showSupport = false
        showDockIcon = true
        menuBarIconVariant = .defaultMenuBar
        appIconVariant = .defaultAppIcon
        showMenuBarStatusText = true
        captureSelections = true
        selectionCaptureMode = .dragSelectionsOnly
        captureDoubleClickSelections = false
        captureTripleClickSelections = false
        captureShiftArrowSelections = false
        captureCommandASelections = false
        captureFileSelections = false
        clipboardLinkMode = .separate
        showCaptureToasts = true
        showToastSourceLabel = false
        captureToastSize = Self.defaultCaptureToastSize
        captureToastDisplaySeconds = Self.defaultCaptureToastDisplaySeconds
        selectionCaptureDebounceMilliseconds = 40
        selectionIntentWindowMilliseconds = Self.defaultSelectionIntentWindowMilliseconds
        middleClickTriggerEnabled = true
        keyboardShortcutTriggerEnabled = false
        externalTriggerEnabled = false
        preserveClipboard = true
        plainTextOnly = true
        clearAfterPaste = false
        sensitiveTextFiltering = true
        minimumSelectionLength = 1
        maximumSelectionLength = 10_000
        maximumFileSelectionCount = 50
        queueSize = 5
        pasteMode = .latest
        blockedBundleIdentifiers = [
            "com.1password.1password",
            "com.agilebits.onepassword7",
            "com.bitwarden.desktop",
            "com.apple.keychainaccess",
        ]
        passThroughBundleIdentifiers = []
        appCompatibilityRules = []
        completedManualVerificationIDs = []
    }

}
