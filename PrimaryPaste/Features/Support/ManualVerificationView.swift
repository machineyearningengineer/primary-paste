import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct Phase6ManualVerificationDisclosureCard: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var permissions: PermissionsCoordinator
    @Binding var isExpanded: Bool
    let runClipboardLinkProbe: () -> Void
    let runPrivacyProbe: () -> Void
    let runAppProbes: () -> Void
    let copyManualVerificationReportText: (String) -> Void

    private let items = ManualVerificationItem.all

    private var completedCount: Int {
        items.filter { preferences.isManualVerificationComplete($0.id) }.count
    }

    private var totalCount: Int {
        items.count
    }

    private var isComplete: Bool {
        completedCount == totalCount
    }

    private var detailText: String {
        if isExpanded {
            return "Confirm behavior in the apps you use."
        }
        return "Track checks that require real apps, permissions, or gestures."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                SettingsCardHeader(
                    title: "App Checks",
                    detail: detailText,
                    systemImage: isComplete ? "checkmark.seal.fill" : "figure.walk.motion",
                    tint: isComplete ? Color.green : Color.accentColor
                ) {
                    Spacer()
                    StatusBadge(
                        isComplete: isComplete,
                        text: isComplete ? "Complete" : "\(completedCount) of \(totalCount)",
                        tone: isComplete ? .success : .progress
                    )
                    Button(isExpanded ? "Hide" : "Open") {
                        withAnimation(.snappy(duration: 0.22)) {
                            isExpanded.toggle()
                        }
                    }
                    .controlSize(.small)
                }

                ProgressView(value: totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount))
                    .tint(isComplete ? Color.green : Color.accentColor)
            }

            if isExpanded {
                Phase6ManualVerificationCard(
                    appState: appState,
                    preferences: preferences,
                    permissions: permissions,
                    runClipboardLinkProbe: runClipboardLinkProbe,
                    runPrivacyProbe: runPrivacyProbe,
                    runAppProbes: runAppProbes,
                    copyManualVerificationReportText: copyManualVerificationReportText
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct Phase6ManualVerificationCard: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var permissions: PermissionsCoordinator
    let runClipboardLinkProbe: () -> Void
    let runPrivacyProbe: () -> Void
    let runAppProbes: () -> Void
    let copyManualVerificationReportText: (String) -> Void

    @State private var didCopyReport = false
    @State private var didResetSignals = false
    @State private var didRestoreTestSettings = false
    @State private var didRunAppProbes = false
    @State private var didAcceptEvidence = false
    @State private var textCapRestoreValue: Int?
    @State private var finderCapRestoreValue: Int?
    @State private var finderCaptureRestoreValue: Bool?
    @State private var selectedGuideID: String?
    @State private var preparedTargetLabel: String?
    @State private var showsManualEvidenceDetails = false
    @State private var showsAllManualChecks = false

    private let items = ManualVerificationItem.all

    private var completedCount: Int {
        items.filter { preferences.isManualVerificationComplete($0.id) }.count
    }

    private var progress: Double {
        guard !items.isEmpty else { return 0 }
        return Double(completedCount) / Double(items.count)
    }

    private var openCheckCount: Int {
        items.count - completedCount
    }

    private var evidenceBackedItems: [ManualVerificationItem] {
        items.filter { item in
            switch item.proofKind {
            case .appProbe, .runtimeEvidence:
                return true
            case .settingsAndHuman, .humanCheck:
                return false
            }
        }
    }

    private var evidenceReadyCount: Int {
        evidenceBackedItems.filter { evidence(for: $0)?.isPositive == true }.count
    }

    private var evidenceReadyOpenItems: [ManualVerificationItem] {
        evidenceBackedItems.filter { item in
            evidence(for: item)?.isPositive == true
                && !preferences.isManualVerificationComplete(item.id)
        }
    }

    private var evidenceGapCount: Int {
        evidenceBackedItems.count - evidenceReadyCount
    }

    private var missingTargetCount: Int {
        textCaptureCoverage.missing.count
            + editablePasteCoverage.missing.count
            + browserPassThroughCoverage.missing.count
    }

    private var firstIncompleteItem: ManualVerificationItem? {
        items.first { !preferences.isManualVerificationComplete($0.id) }
    }

    private var nextUnprovenTitle: String {
        if let evidenceGap = evidenceBackedItems.first(where: { evidence(for: $0)?.isPositive != true }) {
            return evidenceGap.title
        }
        if let firstIncompleteItem {
            return firstIncompleteItem.title
        }
        return "All checks"
    }

    private var guidedItem: ManualVerificationItem? {
        if let selectedGuideID,
            let selectedItem = items.first(where: { $0.id == selectedGuideID })
        {
            return selectedItem
        }
        return firstIncompleteItem
    }

    private var guidedItemLabel: String {
        selectedGuideID == nil ? "Up Next" : "Guided Check"
    }

    private var hasTransientStatus: Bool {
        didCopyReport
            || didResetSignals
            || didRunAppProbes
            || didAcceptEvidence
            || preparedTargetLabel != nil
            || hasTemporaryTestSettings
            || didRestoreTestSettings
    }

    private var accessibilityIsReadyForCurrentSettings: Bool {
        !preferences.shouldUseAccessibility || permissions.isAccessibilityTrusted
    }

    private var inputMonitoringIsReadyForCurrentSettings: Bool {
        !preferences.shouldMonitorGlobalEvents || permissions.isInputMonitoringTrusted
    }

    private var setupPermissionsReadyForCurrentSettings: Bool {
        accessibilityIsReadyForCurrentSettings && inputMonitoringIsReadyForCurrentSettings
    }

    private var textCaptureCoverage: ManualVerificationTargetCoverage {
        targetCoverage(
            observedNames: appState.diagnostics.selectionCaptureSourceNames,
            observedBundleIdentifiers: appState.diagnostics.selectionCaptureSourceBundleIdentifiers,
            targets: [
                ManualVerificationTarget(
                    title: "Browser",
                    tokens: [
                        "Arc", "Safari", "Chrome", "Firefox", "Brave", "company.thebrowser", "com.apple.Safari",
                        "com.google.Chrome", "org.mozilla.firefox", "com.brave.Browser",
                    ]),
                ManualVerificationTarget(title: "Codex", tokens: ["Codex", "com.openai"]),
                ManualVerificationTarget(
                    title: "Terminal",
                    tokens: [
                        "Terminal", "iTerm", "Ghostty", "Warp", "Alacritty", "kitty", "com.apple.Terminal",
                        "com.mitchellh.ghostty",
                    ]),
                ManualVerificationTarget(title: "TextEdit", tokens: ["TextEdit", "com.apple.TextEdit"]),
                ManualVerificationTarget(title: "Finder", tokens: ["Finder", "com.apple.finder"]),
            ]
        )
    }

    private var editablePasteCoverage: ManualVerificationTargetCoverage {
        targetCoverage(
            observedNames: appState.diagnostics.pasteTargetAppNames,
            observedBundleIdentifiers: appState.diagnostics.pasteTargetBundleIdentifiers,
            targets: [
                ManualVerificationTarget(
                    title: "Native field",
                    tokens: [
                        "Primary Paste", "TextEdit", "Notes", "com.abel.primarypaste", "com.apple.TextEdit",
                        "com.apple.Notes",
                    ]),
                ManualVerificationTarget(
                    title: "Web input",
                    tokens: [
                        "Arc", "Safari", "Chrome", "Firefox", "Brave", "company.thebrowser", "com.apple.Safari",
                        "com.google.Chrome", "org.mozilla.firefox", "com.brave.Browser",
                    ]),
                ManualVerificationTarget(title: "Codex composer", tokens: ["Codex", "com.openai"]),
            ]
        )
    }

    private var browserPassThroughCoverage: ManualVerificationTargetCoverage {
        targetCoverage(
            observedNames: appState.diagnostics.passThroughAppNames,
            observedBundleIdentifiers: appState.diagnostics.passThroughBundleIdentifiers,
            targets: [
                ManualVerificationTarget(
                    title: "Browser link/tab",
                    tokens: [
                        "Arc", "Safari", "Chrome", "Firefox", "Brave", "company.thebrowser", "com.apple.Safari",
                        "com.google.Chrome", "org.mozilla.firefox", "com.brave.Browser",
                    ])
            ]
        )
    }

    private func targetCoverage(
        observedNames: [String],
        observedBundleIdentifiers: [String],
        targets: [ManualVerificationTarget]
    ) -> ManualVerificationTargetCoverage {
        let observed = observedNames + observedBundleIdentifiers
        let covered =
            targets
            .filter { target in
                observed.contains { observedValue in
                    target.tokens.contains { token in
                        observedValue.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    }
                }
            }
            .map(\.title)
        let missing = targets.map(\.title).filter { !covered.contains($0) }
        return ManualVerificationTargetCoverage(covered: covered, missing: missing)
    }

    private func targetAction(for targetTitle: String?) -> (title: String, action: () -> Void)? {
        guard let targetTitle else { return nil }
        switch targetTitle {
        case "Browser", "Web input", "Browser link/tab":
            return ("Open Browser", preparedTargetAction("Browser", action: openBrowserTestPage))
        case "Native field", "TextEdit":
            return ("Open TextEdit", preparedTargetAction("TextEdit", action: openTextEditTestDocument))
        case "Finder":
            return ("Open Finder", preparedTargetAction("Finder", action: openFinderHome))
        case "Terminal":
            return ("Open Terminal", preparedTargetAction("Terminal", action: openTerminalTestTarget))
        case "Codex", "Codex composer":
            return ("Open Codex", preparedTargetAction("Codex", action: openCodexTestTarget))
        default:
            return nil
        }
    }

    private func preparedTargetAction(_ label: String, action: @escaping () -> Void) -> () -> Void {
        {
            action()
            preparedTargetLabel = label
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if preparedTargetLabel == label {
                    preparedTargetLabel = nil
                }
            }
        }
    }

    private func guide(for item: ManualVerificationItem) -> ManualVerificationGuide {
        switch item.id {
        case "setup-needed-status":
            if !setupPermissionsReadyForCurrentSettings {
                return ManualVerificationGuide(
                    detail:
                        "Menu bar should stay in setup state until the permissions needed by the current settings are allowed.",
                    actionTitle: "Refresh",
                    action: permissions.refresh
                )
            }
            return ManualVerificationGuide(
                detail:
                    "To recheck this, temporarily revoke one required permission in System Settings and watch the menu bar state.",
                actionTitle: "Open Accessibility",
                action: permissions.openAccessibilitySettings
            )

        case "permission-persistence":
            return ManualVerificationGuide(
                detail:
                    "After this signed app is rebuilt, confirm Accessibility and any currently needed Input Monitoring permission still point at Primary Paste.",
                actionTitle: "Refresh",
                action: permissions.refresh
            )

        case "url-bar-auto-selection":
            return ManualVerificationGuide(
                detail:
                    "Focus a browser address field without dragging. Primary should not change, and Support Details should report an ignored automatic selection change.",
                actionTitle: "Use Safe Mode",
                action: { preferences.selectionCaptureMode = .dragSelectionsOnly },
                secondaryActionTitle: "Open Browser",
                secondaryAction: preparedTargetAction("Browser", action: openBrowserTestPage)
            )

        case "cross-app-text-capture":
            let sourceSummary =
                appState.diagnostics.selectionCaptureSourceNames.isEmpty
                ? "No apps captured yet."
                : "Seen this run: \(appState.diagnostics.selectionCaptureSourceSummary)."
            let nextAction = targetAction(for: textCaptureCoverage.nextMissingTargetTitle)
            return ManualVerificationGuide(
                detail:
                    "Drag-select text in each target app and check the capture toast and Support Details. \(sourceSummary)",
                actionTitle: preferences.captureSelections ? nil : "Enable Capture",
                action: preferences.captureSelections ? nil : { preferences.captureSelections = true },
                secondaryActionTitle: nextAction?.title,
                secondaryAction: nextAction?.action
            )

        case "browser-pass-through":
            let passThroughCount = appState.diagnostics.passThroughAppNames.count
            let passThroughSummary =
                passThroughCount == 0
                ? "No pass-through apps observed yet."
                : "Seen this run: \(appState.diagnostics.passThroughSummary)."
            let nextAction = targetAction(for: browserPassThroughCoverage.nextMissingTargetTitle)
            return ManualVerificationGuide(
                detail:
                    "Middle-click a browser link/tab or the pass-through check. Paste diagnostics should say Passed through. \(passThroughSummary)",
                secondaryActionTitle: nextAction?.title,
                secondaryAction: nextAction?.action
            )

        case "editable-paste":
            let pasteTargetSummary =
                appState.diagnostics.pasteTargetAppNames.isEmpty
                ? "No paste targets observed yet."
                : "Seen this run: \(appState.diagnostics.pasteTargetSummary)."
            let nextAction = targetAction(for: editablePasteCoverage.nextMissingTargetTitle)
            return ManualVerificationGuide(
                detail:
                    "Middle-click a native field, web input, and Codex composer after Primary has an item ready. \(pasteTargetSummary)",
                actionTitle: "Load Sample",
                action: preparedTargetAction(
                    "Sample",
                    action: {
                        appState.primaryStore.record(
                            "Primary Paste sample",
                            sourceAppName: "Primary Paste",
                            sourceBundleIdentifier: Bundle.main.bundleIdentifier
                        )
                    }),
                secondaryActionTitle: nextAction?.title,
                secondaryAction: nextAction?.action
            )

        case "native-clipboard-default":
            let isSeparate = preferences.clipboardLinkMode == .separate
            return ManualVerificationGuide(
                detail:
                    "With Clipboard Link Separate, run the contained check to prove a normal clipboard write does not replace Primary. Cmd+C and Cmd+V still deserve one quick human check.",
                actionTitle: isSeparate ? "Check Default" : "Set Separate",
                action: isSeparate ? runClipboardLinkProbe : { preferences.clipboardLinkMode = .separate }
            )

        case "clipboard-link-modes":
            return ManualVerificationGuide(
                detail:
                    "Run the self-capture guard and the current mode check, then test Import Copies and Mirror Selections without feedback loops.",
                actionTitle: "Check Clipboard",
                action: runClipboardLinkProbe
            )

        case "finder-file-paste":
            if !preferences.captureFileSelections {
                return ManualVerificationGuide(
                    detail:
                        "Turn file capture on, then prepare a harmless Finder selection and middle-click into an app that accepts file paste.",
                    actionTitle: "Enable Files",
                    action: enableFinderCaptureForManualTest,
                    secondaryActionTitle: "Prepare Files",
                    secondaryAction: preparedTargetAction("Finder Files", action: prepareFinderFilePasteTest)
                )
            }
            if !permissions.isFinderAutomationTrusted {
                return ManualVerificationGuide(
                    detail: "Finder Automation is needed before selected files can become a Primary item.",
                    actionTitle: "Allow Finder",
                    action: permissions.requestFinderAutomationPermission,
                    secondaryActionTitle: "Open Finder",
                    secondaryAction: preparedTargetAction("Finder", action: openFinderHome)
                )
            }
            return ManualVerificationGuide(
                detail: "Prepare a harmless Finder selection, then paste into a target app that accepts attachments.",
                actionTitle: "Prepare Files",
                action: preparedTargetAction("Finder Files", action: prepareFinderFilePasteTest),
                secondaryActionTitle: "Open Finder",
                secondaryAction: preparedTargetAction("Finder", action: openFinderHome)
            )

        case "text-limit-toast":
            return ManualVerificationGuide(
                detail:
                    "Use a low cap briefly, select longer text, and confirm the warning toast leaves Primary unchanged.",
                actionTitle: "Set 500 Cap",
                action: preparedTargetAction("Text Cap", action: prepareTextLimitTest),
                secondaryActionTitle: "Open TextEdit",
                secondaryAction: preparedTargetAction("TextEdit", action: openTextEditTestDocument)
            )

        case "finder-limit-toast":
            if !preferences.captureFileSelections {
                return ManualVerificationGuide(
                    detail:
                        "Turn file capture on, then prepare an over-limit Finder selection to confirm the warning toast.",
                    actionTitle: "Enable Files",
                    action: enableFinderCaptureForManualTest,
                    secondaryActionTitle: "Prepare Limit Check",
                    secondaryAction: preparedTargetAction("Finder Limit", action: prepareFinderLimitTest)
                )
            }
            if !permissions.isFinderAutomationTrusted {
                return ManualVerificationGuide(
                    detail: "Finder Automation is needed before Primary can detect over-limit Finder selections.",
                    actionTitle: "Allow Finder",
                    action: permissions.requestFinderAutomationPermission,
                    secondaryActionTitle: "Open Finder",
                    secondaryAction: preparedTargetAction("Finder", action: openFinderHome)
                )
            }
            return ManualVerificationGuide(
                detail: "Prepare two temp files while the cap is one item, then watch for the warning toast.",
                actionTitle: "Prepare Limit Check",
                action: preparedTargetAction("Finder Limit", action: prepareFinderLimitTest),
                secondaryActionTitle: "Open Finder",
                secondaryAction: preparedTargetAction("Finder", action: openFinderHome)
            )

        case "privacy-guards":
            return ManualVerificationGuide(
                detail:
                    "Run the self-test, then check Private Mode, blocked apps, secure fields, and sensitive-looking text.",
                actionTitle: "Check Privacy",
                action: runPrivacyProbe
            )

        default:
            return ManualVerificationGuide(detail: item.detail, actionTitle: nil, action: nil)
        }
    }

    private func evidence(for item: ManualVerificationItem) -> ManualVerificationEvidence? {
        switch item.id {
        case "setup-needed-status":
            if !setupPermissionsReadyForCurrentSettings {
                return ManualVerificationEvidence(text: "Needs setup", isPositive: false)
            }
            return ManualVerificationEvidence(text: "Ready", isPositive: true)

        case "permission-persistence":
            return setupPermissionsReadyForCurrentSettings
                ? ManualVerificationEvidence(text: "Allowed now", isPositive: true)
                : nil

        case "url-bar-auto-selection":
            if appState.diagnostics.lastSelectionDecision.hasPrefix("Ignored automatic selection change") {
                return ManualVerificationEvidence(
                    text: "Auto-selection ignored",
                    isPositive: true,
                    detail:
                        "Primary saw an automatic selection/focus change and ignored it without reading selected text."
                )
            }
            return preferences.selectionCaptureMode == .dragSelectionsOnly
                ? ManualVerificationEvidence(
                    text: "Guard on",
                    isPositive: false,
                    detail:
                        "Drag-only mode is enabled. Focus a browser address field to produce ignored-auto-selection evidence."
                )
                : ManualVerificationEvidence(text: "Review mode", isPositive: false)

        case "cross-app-text-capture":
            if textCaptureCoverage.hasEvidence {
                return ManualVerificationEvidence(
                    text: textCaptureCoverage.badgeText,
                    isPositive: textCaptureCoverage.isComplete,
                    detail: textCaptureCoverage.detailText
                )
            }
            return appState.diagnostics.lastSelectionDecision.hasPrefix("Captured")
                ? ManualVerificationEvidence(
                    text: "Captured once", isPositive: false, detail: textCaptureCoverage.detailText)
                : nil

        case "browser-pass-through":
            if browserPassThroughCoverage.hasEvidence {
                return ManualVerificationEvidence(
                    text: "Browser passed",
                    isPositive: browserPassThroughCoverage.isComplete,
                    detail: browserPassThroughCoverage.detailText
                )
            }
            if !appState.diagnostics.passThroughAppNames.isEmpty {
                return ManualVerificationEvidence(
                    text: "Check only",
                    isPositive: false,
                    detail: browserPassThroughCoverage.detailText
                )
            }
            return PastePassThroughEvidence.confirmsTargetSafety(appState.diagnostics.lastPasteDecision)
                ? ManualVerificationEvidence(
                    text: "Observed", isPositive: false, detail: browserPassThroughCoverage.detailText)
                : nil

        case "editable-paste":
            if editablePasteCoverage.hasEvidence {
                return ManualVerificationEvidence(
                    text: editablePasteCoverage.badgeText,
                    isPositive: editablePasteCoverage.isComplete,
                    detail: editablePasteCoverage.detailText
                )
            }
            return pasteSucceeded
                ? ManualVerificationEvidence(
                    text: "Observed", isPositive: false, detail: editablePasteCoverage.detailText)
                : nil

        case "native-clipboard-default":
            guard preferences.clipboardLinkMode == .separate else {
                return ManualVerificationEvidence(
                    text: preferences.clipboardLinkMode.title,
                    isPositive: false,
                    detail: "Set Clipboard Link to Separate before proving the native clipboard default."
                )
            }
            return appState.diagnostics.nativeClipboardDefaultProbePassed
                ? ManualVerificationEvidence(
                    text: "Default passed",
                    isPositive: true,
                    detail: appState.diagnostics.lastNativeClipboardDefaultProbe
                )
                : ManualVerificationEvidence(
                    text: "Separate",
                    isPositive: false,
                    detail: "Run Check Default to confirm normal clipboard writes stay out of Primary."
                )

        case "clipboard-link-modes":
            if appState.diagnostics.clipboardLinkModeProbePassed,
                appState.diagnostics.clipboardLinkModeProbeModeTitle == preferences.clipboardLinkMode.title
            {
                return ManualVerificationEvidence(text: "Mode passed", isPositive: true)
            }
            return appState.diagnostics.clipboardSelfCaptureProbePassed
                ? ManualVerificationEvidence(text: "Guard passed", isPositive: true)
                : nil

        case "finder-file-paste":
            if appState.diagnostics.lastFileSelectionDecision.hasPrefix("Captured") {
                return ManualVerificationEvidence(
                    text: "Item ready",
                    isPositive: false,
                    detail:
                        "Primary captured the Finder selection. Confirm paste or attach in the target app before marking verified."
                )
            }
            if primaryHasFinderPayload {
                return ManualVerificationEvidence(
                    text: "Item ready",
                    isPositive: false,
                    detail:
                        "Primary has Finder files ready. Confirm paste or attach in the target app before marking verified."
                )
            }
            return nil

        case "text-limit-toast":
            return appState.diagnostics.lastSelectionDecision.hasPrefix("Too long")
                ? ManualVerificationEvidence(text: "Warning seen", isPositive: true)
                : nil

        case "finder-limit-toast":
            return appState.diagnostics.lastFileSelectionDecision.hasPrefix("Too many")
                ? ManualVerificationEvidence(text: "Warning seen", isPositive: true)
                : nil

        case "privacy-guards":
            if appState.diagnostics.privacyProbePassed {
                return ManualVerificationEvidence(
                    text: "Sensitive probe",
                    isPositive: false,
                    detail:
                        "Sensitive-looking text is blocked. Still verify Private Mode, blocked apps, and secure fields by hand."
                )
            }
            return preferences.sensitiveTextFiltering
                ? ManualVerificationEvidence(
                    text: "Filtering on",
                    isPositive: false,
                    detail:
                        "Run the sensitive-text self-test, then verify Private Mode, blocked apps, and secure fields by hand."
                )
                : ManualVerificationEvidence(text: "Filtering off", isPositive: false)

        default:
            return nil
        }
    }

    private var pasteSucceeded: Bool {
        let decision = appState.diagnostics.lastPasteDecision
        return decision.hasPrefix("Paste requested")
            || decision.hasPrefix("Paste command sent")
            || decision.hasPrefix("Inserted text directly")
            || decision.hasPrefix("Typed text")
            || decision.hasPrefix("Clipboard-restored text pasted")
            || decision.hasPrefix("Clipboard-only payload pasted")
    }

    private var primaryHasFinderPayload: Bool {
        guard
            let current = appState.primaryStore.current,
            case .pasteboard(let snapshot) = current.payload
        else {
            return false
        }
        return !snapshot.fileURLs.isEmpty
    }

    private var runtimeEvidenceRunStartedText: String {
        Self.runtimeEvidenceRunDateFormatter.string(from: appState.diagnostics.runtimeEvidenceRunStartedAt)
    }

    private var hasTemporaryTestSettings: Bool {
        textCapRestoreValue != nil
            || finderCapRestoreValue != nil
            || finderCaptureRestoreValue != nil
    }

    private var appProbeCount: Int {
        items.filter { $0.proofKind == .appProbe }.count
    }

    private var runtimeEvidenceCheckCount: Int {
        items.filter { $0.proofKind == .runtimeEvidence }.count
    }

    private var settingsAndHumanCheckCount: Int {
        items.filter { $0.proofKind == .settingsAndHuman }.count
    }

    private var humanCheckCount: Int {
        items.filter { $0.proofKind == .humanCheck }.count
    }

    private static let runtimeEvidenceRunDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func openBrowserTestPage() {
        let fileManager = FileManager.default
        let folderURL = fileManager.temporaryDirectory.appendingPathComponent(
            "Primary Paste Phase 6 Browser Check",
            isDirectory: true
        )
        let pageURL = folderURL.appendingPathComponent("index.html")

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try browserTestPageHTML.write(to: pageURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(pageURL)
            appState.diagnostics.recordPasteDecision("Prepared browser check page")
        } catch {
            guard let url = URL(string: "https://example.com") else { return }
            NSWorkspace.shared.open(url)
            appState.diagnostics.recordPasteDecision("Browser check page setup failed")
        }
    }

    private func openFinderHome() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
    }

    private func openTerminalTestTarget() {
        openApplication(at: [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app",
            "/Applications/Terminal.app",
            "/Applications/Ghostty.app",
            "/Applications/iTerm.app",
        ])
        appState.diagnostics.recordSelectionDecision("Prepared Terminal target")
    }

    private func openCodexTestTarget() {
        openApplication(at: [
            "/Applications/Codex.app",
            "/Applications/Codex Computer Use.app",
        ])
        appState.diagnostics.recordPasteDecision("Prepared Codex target")
    }

    private func prepareTextLimitTest() {
        rememberTextCapForManualTest(target: 500)
        preferences.maximumSelectionLength = 500
    }

    private func enableFinderCaptureForManualTest() {
        rememberFinderSettingsForManualTest(
            targetCap: preferences.maximumFileSelectionCount,
            targetCapture: true
        )
        preferences.captureFileSelections = true
    }

    private func prepareFinderFilePasteTest() {
        rememberFinderSettingsForManualTest(
            targetCap: preferences.maximumFileSelectionCount,
            targetCapture: true
        )
        preferences.captureFileSelections = true
        guard permissions.isFinderAutomationTrusted else {
            permissions.requestFinderAutomationPermission()
            return
        }

        let count = max(1, min(3, preferences.maximumFileSelectionCount))
        prepareFinderTestSelection(fileCount: count, decisionPrefix: "Prepared Finder file paste check")
    }

    private func prepareFinderLimitTest() {
        rememberFinderSettingsForManualTest(targetCap: 1, targetCapture: true)
        preferences.captureFileSelections = true
        preferences.maximumFileSelectionCount = 1
        guard permissions.isFinderAutomationTrusted else {
            permissions.requestFinderAutomationPermission()
            return
        }

        prepareFinderTestSelection(fileCount: 2, decisionPrefix: "Prepared Finder over-limit check")
    }

    private func rememberTextCapForManualTest(target: Int) {
        guard preferences.maximumSelectionLength != target else { return }
        if textCapRestoreValue == nil {
            textCapRestoreValue = preferences.maximumSelectionLength
        }
    }

    private func rememberFinderSettingsForManualTest(targetCap: Int, targetCapture: Bool) {
        if preferences.maximumFileSelectionCount != targetCap, finderCapRestoreValue == nil {
            finderCapRestoreValue = preferences.maximumFileSelectionCount
        }
        if preferences.captureFileSelections != targetCapture, finderCaptureRestoreValue == nil {
            finderCaptureRestoreValue = preferences.captureFileSelections
        }
    }

    private func restoreTemporaryTestSettings() {
        if let textCapRestoreValue {
            preferences.maximumSelectionLength = textCapRestoreValue
        }
        if let finderCapRestoreValue {
            preferences.maximumFileSelectionCount = finderCapRestoreValue
        }
        if let finderCaptureRestoreValue {
            preferences.captureFileSelections = finderCaptureRestoreValue
        }

        textCapRestoreValue = nil
        finderCapRestoreValue = nil
        finderCaptureRestoreValue = nil
        appState.diagnostics.recordSelectionDecision("Restored temporary check settings")
        appState.diagnostics.recordFileSelectionDecision("Restored temporary check settings")
        didRestoreTestSettings = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            didRestoreTestSettings = false
        }
    }

    private func prepareFinderTestSelection(fileCount: Int, decisionPrefix: String) {
        let fileManager = FileManager.default
        let folderURL = fileManager.temporaryDirectory.appendingPathComponent(
            "Primary Paste Phase 6 Finder Check",
            isDirectory: true
        )

        do {
            if fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.removeItem(at: folderURL)
            }
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let selectedURLs = try (1...max(fileCount, 1)).map { index in
                let url = folderURL.appendingPathComponent("primary-paste-check-\(index).txt")
                try "Primary Paste Finder check file \(index)\n".write(to: url, atomically: true, encoding: .utf8)
                return url
            }

            selectFinderItems(selectedURLs, folderURL: folderURL)
            appState.diagnostics.recordFileSelectionDecision("\(decisionPrefix): \(selectedURLs.count) item(s)")
        } catch {
            appState.diagnostics.recordFileSelectionDecision("Finder test setup failed")
            NSWorkspace.shared.open(folderURL)
        }
    }

    private func selectFinderItems(_ urls: [URL], folderURL: URL) {
        let selectedPaths =
            urls
            .map { appleScriptStringLiteral($0.path) }
            .joined(separator: ", ")
        let folderPath = appleScriptStringLiteral(folderURL.path)

        let source = """
            set selectedPaths to {\(selectedPaths)}
            set selectedAliases to {}
            repeat with selectedPath in selectedPaths
                set end of selectedAliases to (POSIX file selectedPath) as alias
            end repeat
            tell application id "com.apple.finder"
                activate
                open ((POSIX file \(folderPath)) as alias)
                delay 0.15
                set selection to selectedAliases
            end tell
            """

        guard let script = NSAppleScript(source: source) else {
            NSWorkspace.shared.open(folderURL)
            return
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if errorInfo != nil {
            appState.diagnostics.recordFileSelectionDecision("Finder test selection failed")
            NSWorkspace.shared.open(folderURL)
        }
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func openTextEditTestDocument() {
        let fileManager = FileManager.default
        let folderURL = fileManager.temporaryDirectory.appendingPathComponent(
            "Primary Paste Phase 6 Text Check",
            isDirectory: true
        )
        let documentURL = folderURL.appendingPathComponent("Primary Paste Text Check.txt")

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try textEditTestDocument.write(to: documentURL, atomically: true, encoding: .utf8)
            openTextDocument(documentURL)
            appState.diagnostics.recordSelectionDecision("Prepared TextEdit check document")
        } catch {
            openApplication(at: [
                "/System/Applications/TextEdit.app",
                "/Applications/TextEdit.app",
            ])
            appState.diagnostics.recordSelectionDecision("TextEdit check document setup failed")
        }
    }

    private func openTextDocument(_ documentURL: URL) {
        let applicationPaths = [
            "/System/Applications/TextEdit.app",
            "/Applications/TextEdit.app",
        ]

        guard let appPath = applicationPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            NSWorkspace.shared.open(documentURL)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [documentURL],
            withApplicationAt: URL(fileURLWithPath: appPath, isDirectory: true),
            configuration: configuration
        )
    }

    private func openApplication(at paths: [String]) {
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    private var browserTestPageHTML: String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Primary Paste Browser Test</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
            body { margin: 0; padding: 32px; line-height: 1.45; background: Canvas; color: CanvasText; }
            main { max-width: 760px; margin: 0 auto; display: grid; gap: 18px; }
            section { border: 1px solid color-mix(in srgb, CanvasText 14%, transparent); border-radius: 12px; padding: 18px; }
            a { font-weight: 700; color: LinkText; }
            input, textarea { box-sizing: border-box; width: 100%; padding: 12px; border-radius: 10px; border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); font: inherit; }
            textarea { min-height: 110px; resize: vertical; }
            p { margin: 0 0 10px; }
          </style>
        </head>
        <body>
          <main>
            <h1>Primary Paste Browser Check</h1>
            <section>
              <p>Middle-click this link to confirm browser pass-through keeps native tab behavior.</p>
              <a href="https://example.com/primary-paste-pass-through-test">Middle-click pass-through link</a>
            </section>
            <section>
              <p>Drag-select this sentence to check browser text selection capture without using the address bar.</p>
              <p>Primary Paste should capture this browser paragraph when you deliberately drag over the text.</p>
            </section>
            <section>
              <p>Middle-click inside these editable fields to check web-input paste.</p>
              <input aria-label="Primary Paste input check" placeholder="Middle-click paste here">
              <textarea aria-label="Primary Paste textarea check" placeholder="Middle-click paste here too"></textarea>
            </section>
          </main>
        </body>
        </html>
        """
    }

    private var textEditTestDocument: String {
        """
        Primary Paste TextEdit Check

        Short selection:
        Drag over this sentence to confirm native text selection capture.

        Long selection:
        Drag from here through several lines to confirm the toast updates as the selection grows. Primary Paste should keep the preview to one line, show useful metrics only when the text gets long enough, and avoid replacing Primary with a clipped partial item when a configured cap is exceeded.

        Cap check paragraph:
        This paragraph is intentionally long enough to test the 500 character warning path. Select this whole paragraph after pressing Set 500 Cap in the Troubleshooting Guide. The expected behavior is a subtle warning toast, no partial capture, and the previous Primary item should remain available for middle-click paste. Keep selecting through this paragraph until the highlighted range clearly passes the configured limit so the refusal path has a fair chance to run.
        """
    }

    private var manualVerificationReport: String {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let checklist = items.map { item in
            let status = preferences.isManualVerificationComplete(item.id) ? "Verified" : "Open"
            let itemEvidence = evidence(for: item)
            let manualEvidenceNote =
                status == "Verified" && itemEvidence?.isPositive != true
                ? "Manual check without complete runtime evidence"
                : nil
            let evidenceText = [itemEvidence?.text, itemEvidence?.detail, manualEvidenceNote]
                .compactMap { $0 }
                .joined(separator: " - ")
            let reportEvidenceText = evidenceText.isEmpty ? "No runtime evidence yet" : evidenceText
            return "- [\(status)] [\(item.proofKind.title)] \(item.group.title) / \(item.title): \(reportEvidenceText)"
        }.joined(separator: "\n")

        return """
            Primary Paste Manual Checks Report
            Generated: \(generatedAt)
            Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")

            Progress
            Verified: \(completedCount) of \(items.count)

            Unproven Summary
            Open Checks: \(openCheckCount)
            Evidence Ready: \(evidenceReadyCount) of \(evidenceBackedItems.count)
            Evidence Gaps: \(evidenceGapCount)
            Missing Target Classes: \(missingTargetCount)
            Next Unproven: \(nextUnprovenTitle)

            Permissions
            Accessibility: \(preferences.shouldUseAccessibility ? (permissions.isAccessibilityTrusted ? "Allowed" : "Missing") : "Optional/off")
            Input Monitoring: \(preferences.shouldMonitorGlobalEvents ? (permissions.isInputMonitoringTrusted ? "Allowed" : "Missing") : "Optional/off")
            Finder Automation: \(permissions.isFinderAutomationTrusted ? "Allowed" : (preferences.captureFileSelections ? "Missing" : "Optional/off"))

            Runtime Evidence
            Run Started: \(runtimeEvidenceRunStartedText)
            Selection Sources: \(appState.diagnostics.selectionCaptureSourceSummary)
            Paste Targets: \(appState.diagnostics.pasteTargetSummary)
            Pass-Through Apps: \(appState.diagnostics.passThroughSummary)
            Clipboard Self-Capture Guard: \(appState.diagnostics.clipboardSelfCaptureProbePassed ? "Passed" : "Open")
            Clipboard Link Mode Probe: \(appState.diagnostics.clipboardLinkModeProbePassed ? "Passed" : "Open") (\(appState.diagnostics.clipboardLinkModeProbeModeTitle.isEmpty ? "none" : appState.diagnostics.clipboardLinkModeProbeModeTitle))
            Native Clipboard Default Probe: \(appState.diagnostics.nativeClipboardDefaultProbePassed ? "Passed" : "Open") - \(appState.diagnostics.lastNativeClipboardDefaultProbe)
            Privacy Probe: \(appState.diagnostics.privacyProbePassed ? "Passed" : "Open")

            Target Coverage
            Selection: \(textCaptureCoverage.badgeText) - \(textCaptureCoverage.nextTargetText)
            Paste: \(editablePasteCoverage.badgeText) - \(editablePasteCoverage.nextTargetText)
            Pass-through: \(browserPassThroughCoverage.badgeText) - \(browserPassThroughCoverage.nextTargetText)

            Proof Types
            Scripted: phase6_verify and phase6_smoke cover app identity, setup opening, status labels, diagnostics wiring, and optional clipboard restore.
            App Probes: \(appProbeCount) checks can be exercised by contained Primary Paste self-tests.
            Runtime Evidence: \(runtimeEvidenceCheckCount) checks can collect matching source, target, or warning evidence during this run.
            Setting + Human: \(settingsAndHumanCheckCount) checks can confirm settings but still need native behavior verification.
            Human Checks: \(humanCheckCount) checks still require hands-on confirmation.

            Last Decisions
            Selection: \(appState.diagnostics.lastSelectionDecision)
            Clipboard: \(appState.diagnostics.lastClipboardDecision)
            Native Clipboard Default: \(appState.diagnostics.lastNativeClipboardDefaultProbe)
            Paste: \(appState.diagnostics.lastPasteDecision)
            Finder: \(appState.diagnostics.lastFileSelectionDecision)
            Privacy: \(appState.diagnostics.lastPrivacyProbe)

            Settings
            Capture Style: \(preferences.selectionCaptureMode.title)
            Clipboard Link: \(preferences.clipboardLinkMode.title)
            Preserve Clipboard: \(preferences.preserveClipboard)
            Editable Fields Only: Always
            Outside Editable Fields Pass Through: Always
            Finder File Capture: \(preferences.captureFileSelections)
            Text Maximum: \(preferences.maximumSelectionLength == 0 ? "Unlimited" : preferences.maximumSelectionLength.formatted())
            Finder File Maximum: \(preferences.maximumFileSelectionCount.formatted())
            Temporary Check Settings: \(hasTemporaryTestSettings ? "Temporary changes pending restore" : "Normal")

            Checklist
            \(checklist)
            """
    }

    private func copyManualVerificationReport() {
        copyManualVerificationReportText(manualVerificationReport)
        didCopyReport = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            didCopyReport = false
        }
    }

    private func startFreshManualVerificationRun() {
        appState.diagnostics.resetRuntimeEvidence()
        didResetSignals = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            didResetSignals = false
        }
    }

    private func runContainedAppProbes() {
        runAppProbes()
        didRunAppProbes = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            didRunAppProbes = false
        }
    }

    private func acceptEvidenceReadyChecks() {
        let readyItems = evidenceReadyOpenItems
        guard !readyItems.isEmpty else { return }

        readyItems.forEach { item in
            preferences.setManualVerification(item.id, isComplete: true)
        }
        if let selectedGuideID,
            readyItems.contains(where: { $0.id == selectedGuideID })
        {
            self.selectedGuideID = nil
        }

        didAcceptEvidence = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            didAcceptEvidence = false
        }
    }

    var body: some View {
        SettingsCard {
            SettingsCardHeader(
                title: "Troubleshooting Guide",
                detail: "Walk through the remaining real-world checks without crowding normal setup.",
                systemImage: completedCount == items.count ? "checkmark.seal.fill" : "figure.walk.motion",
                tint: completedCount == items.count ? Color.green : Color.accentColor
            ) {
                Spacer()
                StatusBadge(
                    isComplete: completedCount == items.count,
                    text: completedCount == items.count ? "Complete" : "Open",
                    tone: completedCount == items.count ? .success : .progress
                )
                if !evidenceReadyOpenItems.isEmpty {
                    Button("Accept Seen", action: acceptEvidenceReadyChecks)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                ManualVerificationActionMenu(
                    copyReport: copyManualVerificationReport,
                    runAppProbes: runContainedAppProbes,
                    startFreshRun: startFreshManualVerificationRun,
                    restoreTestSettings: restoreTemporaryTestSettings,
                    resetVerification: preferences.resetManualVerification,
                    hasTemporaryTestSettings: hasTemporaryTestSettings,
                    canReset: completedCount > 0
                )
            }

            if hasTransientStatus {
                HStack(spacing: 8) {
                    if didCopyReport {
                        StatusBadge(isComplete: true, text: "Report copied")
                    }
                    if didResetSignals {
                        StatusBadge(isComplete: true, text: "Signals reset")
                    }
                    if didRunAppProbes {
                        StatusBadge(isComplete: true, text: "Checks started")
                    }
                    if didAcceptEvidence {
                        StatusBadge(isComplete: true, text: "Seen checks accepted")
                    }
                    if let preparedTargetLabel {
                        StatusBadge(isComplete: true, text: "Prepared \(preparedTargetLabel)")
                    }
                    if hasTemporaryTestSettings {
                        StatusBadge(isComplete: false, text: "Check settings changed")
                    }
                    if didRestoreTestSettings {
                        StatusBadge(isComplete: true, text: "Settings restored")
                    }
                }
            }

            ProgressView(value: progress)
                .tint(completedCount == items.count ? Color.green : Color.accentColor)

            ManualVerificationFocusStrip(
                openCheckCount: openCheckCount,
                evidenceReadyCount: evidenceReadyCount,
                evidenceBackedCount: evidenceBackedItems.count,
                missingTargetCount: missingTargetCount,
                nextUnprovenTitle: nextUnprovenTitle
            )

            if let guidedItem {
                ManualVerificationGuideCard(
                    label: guidedItemLabel,
                    item: guidedItem,
                    guide: guide(for: guidedItem),
                    evidence: evidence(for: guidedItem),
                    isVerified: preferences.isManualVerificationComplete(guidedItem.id),
                    markVerified: {
                        preferences.setManualVerification(guidedItem.id, isComplete: true)
                        if selectedGuideID == guidedItem.id {
                            selectedGuideID = nil
                        }
                    }
                )
            }

            SettingsDisclosureButton(isExpanded: $showsManualEvidenceDetails) {
                Text(showsManualEvidenceDetails ? "Hide run details" : "Show run details")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if showsManualEvidenceDetails {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                    ManualVerificationGapStrip(
                        openCheckCount: openCheckCount,
                        evidenceReadyCount: evidenceReadyCount,
                        evidenceBackedCount: evidenceBackedItems.count,
                        evidenceGapCount: evidenceGapCount,
                        missingTargetCount: missingTargetCount,
                        nextUnprovenTitle: nextUnprovenTitle
                    )

                    ManualVerificationSignalStrip(
                        runStartedText: runtimeEvidenceRunStartedText,
                        sourceAppCount: appState.diagnostics.selectionCaptureSourceNames.count,
                        pasteTargetCount: appState.diagnostics.pasteTargetAppNames.count,
                        passThroughAppCount: appState.diagnostics.passThroughAppNames.count,
                        clipboardProbeReady: appState.diagnostics.clipboardLinkModeProbePassed
                            && appState.diagnostics.clipboardLinkModeProbeModeTitle
                                == preferences.clipboardLinkMode.title,
                        nativeDefaultProbeReady: preferences.clipboardLinkMode == .separate
                            && appState.diagnostics.nativeClipboardDefaultProbePassed,
                        privacyProbeReady: appState.diagnostics.privacyProbePassed
                    )

                    ManualVerificationCoverageStrip(
                        selectionCoverage: textCaptureCoverage,
                        pasteCoverage: editablePasteCoverage,
                        passThroughCoverage: browserPassThroughCoverage
                    )

                    ManualVerificationProofStrip(
                        appProbeCount: appProbeCount,
                        runtimeEvidenceCount: runtimeEvidenceCheckCount,
                        settingsAndHumanCount: settingsAndHumanCheckCount,
                        humanCheckCount: humanCheckCount
                    )
                }
                .padding(.top, 8)
            }

            SettingsDisclosureButton(isExpanded: $showsAllManualChecks) {
                HStack(spacing: 8) {
                    Text(showsAllManualChecks ? "Hide all checks" : "Show all checks")
                        .font(.caption.weight(.semibold))
                    StatusBadge(
                        isComplete: completedCount == items.count,
                        text: "\(completedCount)/\(items.count)",
                        tone: completedCount == items.count ? .success : .progress
                    )
                }
                .foregroundStyle(.secondary)
            }

            if showsAllManualChecks {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()

                    ForEach(ManualVerificationGroup.allCases) { group in
                        let groupItems = items.filter { $0.group == group }
                        ManualVerificationGroupSection(
                            group: group,
                            items: groupItems,
                            completedCount: groupItems.filter { preferences.isManualVerificationComplete($0.id) }.count,
                            selectedGuideID: selectedGuideID ?? guidedItem?.id,
                            isComplete: { preferences.isManualVerificationComplete($0) },
                            setComplete: { preferences.setManualVerification($0, isComplete: $1) },
                            evidence: evidence,
                            selectGuide: { selectedGuideID = $0 }
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

struct ManualVerificationActionMenu: View {
    let copyReport: () -> Void
    let runAppProbes: () -> Void
    let startFreshRun: () -> Void
    let restoreTestSettings: () -> Void
    let resetVerification: () -> Void
    let hasTemporaryTestSettings: Bool
    let canReset: Bool

    var body: some View {
        Menu {
            Button("Copy Report", action: copyReport)
            Button("Run Checks", action: runAppProbes)
            Button("Fresh Run", action: startFreshRun)
            if hasTemporaryTestSettings {
                Button("Restore Check Settings", action: restoreTestSettings)
            }
            Divider()
            Button("Reset", role: .destructive, action: resetVerification)
                .disabled(!canReset)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }
}
