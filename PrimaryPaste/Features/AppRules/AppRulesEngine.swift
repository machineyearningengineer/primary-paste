import AppKit
import ApplicationServices
import Combine
import Foundation

struct AppRuleTarget: Equatable {
    let bundleIdentifier: String
    let displayName: String
}

final class AppRulesEngine: ObservableObject {
    private let preferences: PreferencesStore
    private let selfBundleIdentifier: String?
    private var activationObserver: NSObjectProtocol?

    @Published private(set) var recentlyFocusedApp: AppRuleTarget?

    init(
        preferences: PreferencesStore,
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.preferences = preferences
        self.selfBundleIdentifier = selfBundleIdentifier
        rememberRuleTarget(from: NSWorkspace.shared.frontmostApplication)

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.rememberRuleTarget(from: application)
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    var frontmostBundleIdentifier: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    var frontmostAppName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown App"
    }

    var frontmostApplication: NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    var frontmostRuleTarget: AppRuleTarget? {
        ruleTarget(from: frontmostApplication)
    }

    var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool == true
    }

    func rememberFrontmostRuleTarget() {
        rememberRuleTarget(from: NSWorkspace.shared.frontmostApplication)
    }

    func canCaptureFrontmostApp() -> Bool {
        canCapture(bundleIdentifier: frontmostBundleIdentifier)
    }

    func canCapture(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else { return true }
        return !preferences.blockedBundleIdentifiers.contains(bundleIdentifier)
    }

    func shouldPassThroughFrontmostApp() -> Bool {
        shouldPassThrough(bundleIdentifier: frontmostBundleIdentifier)
    }

    func shouldPassThrough(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else { return false }
        return preferences.passThroughBundleIdentifiers.contains(bundleIdentifier)
    }

    func compatibilityRuleForFrontmostApp() -> AppCompatibilityRule? {
        guard let bundleIdentifier = frontmostBundleIdentifier else { return nil }
        guard !isSelfBundleIdentifier(bundleIdentifier) else { return nil }
        return preferences.compatibilityRule(for: bundleIdentifier)
    }

    func compatibilityRule(for target: AppRuleTarget) -> AppCompatibilityRule? {
        preferences.compatibilityRule(for: normalizedBundleIdentifier(target.bundleIdentifier))
    }

    func setCompatibilityModeForFrontmostApp(_ mode: AppTextIntegrationMode) {
        guard let target = frontmostRuleTarget else { return }
        setCompatibilityMode(mode, for: target)
    }

    func setCompatibilityMode(_ mode: AppTextIntegrationMode, for target: AppRuleTarget) {
        guard let bundleIdentifier = normalizedBundleIdentifier(target.bundleIdentifier) else { return }
        guard !isSelfBundleIdentifier(bundleIdentifier) else { return }

        if mode == .strictAXOnly {
            preferences.removeCompatibilityRule(bundleIdentifier: bundleIdentifier)
            objectWillChange.send()
            return
        }

        preferences.passThroughBundleIdentifiers.removeAll { $0 == bundleIdentifier }
        let existing = preferences.compatibilityRule(for: bundleIdentifier)
        let rule = AppCompatibilityRule(
            bundleIdentifier: bundleIdentifier,
            displayName: target.displayName,
            integrationMode: mode,
            focusBeforePaste: existing?.focusBeforePaste ?? true,
            restoreClipboardAfterPaste: existing?.restoreClipboardAfterPaste ?? true,
            copySelectionDelayMs: existing?.copySelectionDelayMs ?? 120,
            minDragDistance: existing?.minDragDistance ?? 6,
            minSelectionLength: existing?.minSelectionLength ?? 1,
            maxSelectionLength: existing?.maxSelectionLength ?? 20_000
        )
        preferences.setCompatibilityRule(rule)
        objectWillChange.send()
    }

    func removeCompatibilityRule(_ bundleIdentifier: String) {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else { return }
        preferences.removeCompatibilityRule(bundleIdentifier: bundleIdentifier)
        objectWillChange.send()
    }

    func setCompatibilityRule(_ rule: AppCompatibilityRule) {
        guard let bundleIdentifier = normalizedBundleIdentifier(rule.bundleIdentifier) else { return }
        guard !isSelfBundleIdentifier(bundleIdentifier) else { return }
        if rule.integrationMode != .strictAXOnly {
            preferences.passThroughBundleIdentifiers.removeAll { $0 == bundleIdentifier }
        }
        var normalizedRule = rule
        normalizedRule.bundleIdentifier = bundleIdentifier
        preferences.setCompatibilityRule(normalizedRule)
        objectWillChange.send()
    }

    func pauseFrontmostApp() {
        guard let bundleIdentifier = frontmostBundleIdentifier else { return }
        addBlockedBundleIdentifier(bundleIdentifier)
    }

    func addBlockedBundleIdentifier(_ bundleIdentifier: String) {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else { return }
        guard !isSelfBundleIdentifier(bundleIdentifier) else { return }
        guard !preferences.blockedBundleIdentifiers.contains(bundleIdentifier) else { return }
        preferences.blockedBundleIdentifiers.append(bundleIdentifier)
        objectWillChange.send()
    }

    func removeBlockedBundleIdentifier(_ bundleIdentifier: String) {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else { return }
        preferences.blockedBundleIdentifiers.removeAll { $0 == bundleIdentifier }
        objectWillChange.send()
    }

    func addPassThroughBundleIdentifier(_ bundleIdentifier: String) {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else { return }
        guard !isSelfBundleIdentifier(bundleIdentifier) else { return }
        preferences.removeCompatibilityRule(bundleIdentifier: bundleIdentifier)
        guard !preferences.passThroughBundleIdentifiers.contains(bundleIdentifier) else { return }
        preferences.passThroughBundleIdentifiers.append(bundleIdentifier)
        objectWillChange.send()
    }

    func removePassThroughBundleIdentifier(_ bundleIdentifier: String) {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else { return }
        preferences.passThroughBundleIdentifiers.removeAll { $0 == bundleIdentifier }
        objectWillChange.send()
    }

    func isSelfBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        guard let selfBundleIdentifier else { return false }
        return normalizedBundleIdentifier(bundleIdentifier) == selfBundleIdentifier
    }

    private func rememberRuleTarget(from application: NSRunningApplication?) {
        guard let target = ruleTarget(from: application) else { return }
        guard recentlyFocusedApp != target else { return }
        recentlyFocusedApp = target
    }

    private func ruleTarget(from application: NSRunningApplication?) -> AppRuleTarget? {
        guard let application else { return nil }
        guard let bundleIdentifier = application.bundleIdentifier else { return nil }
        guard !isSelfBundleIdentifier(bundleIdentifier) else { return nil }

        return AppRuleTarget(
            bundleIdentifier: bundleIdentifier,
            displayName: application.localizedName ?? bundleIdentifier
        )
    }

    private func normalizedBundleIdentifier(_ bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else { return nil }
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
